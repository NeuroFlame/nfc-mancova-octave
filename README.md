# NeuroFLAME Computation: MANCOVA, Octave engine (nfc-mancova-octave)

Federated MANCOVA (Multivariate Analysis of Covariance) with Group ICA for multi-site neuroimaging analysis. A NeuroFLAME port of [COINSTAC MANCOVA](https://github.com/trendscenter/coinstac-mancova).

This is the GNU Octave-backed variant of [nfc-mancova](https://github.com/NeuroFlame/nfc-mancova): it runs GIFT's original interpreted `.m` source directly under Octave instead of a MATLAB-Compiler-built executable under MATLAB Runtime (MCR). MathWorks ships MCR only for linux/amd64 and macOS, never linux/arm64, so the MCR-backed computation cannot build natively for Apple Silicon or other arm64 hosts; this variant can, because Octave itself is a plain multi-arch package. The two repos are independent and published as separate images -- pick whichever matches your fleet, or run this one where arm64 native performance matters.

## Overview

**nfc-mancova** enables multi-site MANCOVA analysis without sharing raw neuroimaging data. Each site runs Group ICA locally using the GIFT toolbox; statistical results are then aggregated at the central node to produce global multivariate and univariate analyses across all sites.

The pipeline runs in three phases:

1. **Edge Node** — Group ICA preprocessing and local univariate statistical tests at each site
2. **Central Node** — Covariate aggregation, global univariate pooling, and multivariate MANCOVA
3. **Result Distribution** — Global results returned to all sites

## Architecture

This computation is authored against [computation-nvflare-boilerplate](https://github.com/NeuroFlame/computation-nvflare-boilerplate).
Only `app/code/computation/` is computation-specific; `app/code/framework/`,
`app/code/runtime/`, `app/config/`, `system/`, and the tooling scripts are
boilerplate-managed and are updated with `scripts/migrate_computation.py`
from the boilerplate repository.

The workflow is declared in `app/code/computation/spec.py`:

| Step | Runs on | Function | Purpose |
|---|---|---|---|
| `local_step` | sites | `inputs.load_site_inputs` → `local_math.report_scan_length` | Validate parameters, discover NIfTI/covariate files, report scan length when `common_timepoints` is `true` |
| `remote_step` | central | `remote_math.resolve_common_timepoints` | Resolve the shared timepoint count (minimum across sites) |
| `local_step` | sites | `local_math.run_site_mancova` | Run GIFT Group ICA and local univariate MANCOVA tests; send `*_mancovan_stats_info.mat` files as artifacts |
| `remote_step` | central | `remote_math.aggregate_mancova` | Pool covariates, run GIFT aggregate stats, build the HTML report, and send the aggregation directory back as an artifact |
| `site_output_step` | sites | `remote_math.write_site_outputs` | Unpack the aggregation directory and write `index.html` and `global_mancova_results.json` |

| Module | Role |
|---|---|
| `computation/types.py` | Dataclasses exchanged between steps |
| `computation/gift.py` | Thin NiPype wrappers around GIFT Group ICA and MANCOVA |
| `computation/report.py` | Self-contained HTML report |

## Running this computation

Run the NVFlare simulator in Docker against `test_data/`:

```bash
./run_local_simulation.sh site1,site2            # builds Dockerfile-dev, then simulates
./run_local_simulation.sh site1,site2 --no-build # reuse the image after code-only changes
```

Site results land in `test_output/simulate_job/<site>/` and central results in
`test_output/simulate_job/server/`.

Lint, format-check, compile, and unit tests:

```bash
make check
```

For an interactive shell in the dev image, use `./dockerRun.sh`; `./dockerRunVault.sh`
mounts the real GICA vault data (see the script header).

Publishing production images uses `./dockerPush.sh` (a wrapper for
`scripts/publish_computation_image.py`) with the image coordinates in
`.neuroflame.json`.

## Octave / GIFT Environment

The computation requires GNU Octave (plus its `statistics` package) and
GIFT's interpreted `.m` source tree -- no MATLAB or MATLAB Runtime involved.

| Environment Variable | Description | Default |
|---|---|---|
| `GIFT_HOME` | Root of the GIFT toolbox source | `/app/groupicatv4.0b` |
| `MATLAB_CMD` | Command used by NiPype (via `use_mcr=True`, kept as-is -- see `gift.py`) to launch GIFT's batch scripts | `octave-cli --no-gui --traditional` |

Both Dockerfiles install `octave`/`octave-statistics` from Debian's apt
repos and copy GIFT's `icatb` source from `groupicatv4.0b/icatb` at the repo
root (not committed; see `.gitignore`), so that directory must exist before
building. `icatb` is put on Octave's path for every invocation via a line
appended to `/etc/octaverc` at image build time, not via nipype's `paths`
input -- GIFT's own `addpath` guards (`ismcc`/`isdeployed`) are MATLAB
Compiler built-ins that Octave doesn't define.

GIFT's vendored source needed a number of targeted compatibility patches
to run correctly under Octave (shipped in [`octave_patches/`](octave_patches/)
and copied in at image build time -- see the Dockerfiles for exact copy
points), plus a solver-robustness improvement to the auto-mask threshold
fit. **See [VALIDATION.md](VALIDATION.md)** for the full list of fixes and
the validation results comparing this engine's output against the real
MATLAB-Runtime-backed pipeline on identical data.

## Input Data

Each site's data directory must contain:

- **NIfTI files** (`*.nii` or `*.nii.gz`) — one per subject at the top level of the data directory
- **`*covariates.csv`** — one row per subject (in the same order as sorted NIfTI filenames), one column per covariate
- **`*covariate_keys.csv`** *(optional)* — two columns: `name` and `type` (`"continuous"` or `"categorical"`); all covariates default to continuous if omitted

Standard fMRI preprocessing (realignment, normalisation to MNI space, smoothing) must be applied before running this computation.

## Configuration

Computation parameters are passed via `parameters.json` (path set by `PARAMETERS_FILE_PATH` env var, or `test_data/server/parameters.json` in simulation). See [display_notes.md](display_notes.md) for a full parameter reference and example settings.

### Minimal Example

```json
{
    "scica_template": "NeuroMark.nii",
    "mask": "default&icv",
    "TR": 2,
    "num_components": 53,
    "features": ["spatial", "spectra", "fnc"],
    "run_univariate_tests": true,
    "univariate_test_list": [
        {"regression": {"name": ["age", "diagnosis"]}}
    ],
    "run_mancova": true
}
```

## File Structure

```
nfc-mancova/
├── app/
│   ├── code/
│   │   ├── computation/        # computation-specific code (edit here)
│   │   ├── framework/          # boilerplate-managed
│   │   └── runtime/            # boilerplate-managed NVFlare entrypoints
│   ├── config/                 # boilerplate-managed NVFlare job config
│   └── local_data/             # mask.nii and NeuroMark.nii
├── system/                     # boilerplate-managed provisioning and entrypoints
├── scripts/                    # boilerplate-managed manifest and publishing tools
├── tests/
├── test_data/
├── .neuroflame.json            # computation version and image coordinates
├── display_notes.md
├── Dockerfile-dev / Dockerfile-prod
└── run_local_simulation.sh
```

## References

- Original COINSTAC MANCOVA: https://github.com/trendscenter/coinstac-mancova
- GIFT Toolbox: https://icatb.sourceforge.io/
- NeuroFLAME: https://github.com/NeuroFlame
