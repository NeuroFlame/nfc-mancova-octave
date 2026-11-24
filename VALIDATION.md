# Validation: Octave engine vs. the real MATLAB/MCR pipeline

This document records what changed to make GIFT run under GNU Octave
instead of MATLAB Runtime (MCR), and the evidence that the two engines
produce equivalent results on real data. It exists because this repo
changes the numerical engine underneath a federated statistical
computation, which is a correctness-sensitive thing to do quietly -- every
compatibility fix below was confirmed against a real, reproduced failure
before being applied, not guessed at, and the final validation run compares
real output against the real MATLAB-Runtime-backed pipeline
([nfc-mancova](https://github.com/NeuroFlame/nfc-mancova)) on identical
data and parameters.

## Why this exists

MathWorks ships MATLAB Runtime only for `linux/amd64` and macOS, never
`linux/arm64` -- so `nfc-mancova`'s MCR-backed pipeline cannot build
natively for Apple Silicon or other arm64 hosts. GIFT's actual source is
almost entirely plain, interpreted `.m` code with no toolbox dependencies
this pipeline exercises; swapping the MATLAB-Compiler-built standalone
executable for GNU Octave running that same interpreted source removes the
architecture lock entirely, since Octave itself is a plain multi-arch
package.

## Compatibility fixes

All fixes below were found by direct, isolated reproduction of a real
failure (never assumed), and are scoped as narrowly as the actual defect
allows. Patched files live in [`octave_patches/`](octave_patches/) and are
copied over GIFT's vendored source at image build time (see
`Dockerfile-dev` / `Dockerfile-prod` for the exact copy points and
per-file rationale comments).

| # | Issue | Fix |
|---|---|---|
| 1 | ICASSO's bundled `rindex.m` shadows Octave's built-in `rindex()`, which Octave's own `fileparts.m` depends on internally | Renamed to `icasso_rindex` |
| 2 | `icatb_eval_script.m`'s non-deployed branch loads batch files via `cd` + bare-name `eval()`, which breaks on hyphenated filenames | Swapped to `run(file_name)` |
| 3 | `str2mat`, `textwrap` -- legacy MATLAB functions Octave never implemented | Small forwarding shims (`octave_patches/compat/`) |
| 4 | `do` used as a MATLAB variable name collides with Octave's `do-until` keyword (`@icatb_file_array/{subsref,subsasgn}.m`) | Renamed the variable |
| 5 | `ENFORCE_MAT_FILE_VER='-v7.3'` is set unconditionally in `icatb_defaults.m`; Octave's `save()` can't write v7.3 | Cleared to `''` |
| 6 | 5 compiled SPM8 MEX functions (`spm_slice_vol`, `spm_sample_vol`, `spm_bwlabel`, `mat2file`, `file2mat`) have no Octave-compatible binaries | Compiled from real SPM8 r6313 source via `mkoctfile --mex`, with 2 real 64-bit MEX API fixes (`const int *` → `const mwSize *`); see `octave_patches/build_spm_mex.sh` |
| 7 | `icatb_dpss.p` (DPSS/Slepian taper generation) has no working Octave implementation | Direct from-scratch implementation (tridiagonal-matrix eigenvector method), verified orthonormal to machine precision |
| 8 | `isdeployed`/`ismcc` always return `false` in Octave | Override shims forcing `true`, which also fixes two other fragile code paths that only trigger when `isdeployed` is `false` |
| 9 | `icatb_getGraphics.m`'s `figure(...)` call sets a renderer combo (`'Renderer','zbuffer','RendererMode','manual'`) Octave rejects outright | Stripped those property pairs |
| 10 | GUI dialog construction (`icatb_OptionsWindow.m`) hits 3 separate Octave/uicontrol bugs, used purely to repackage data (always built `visible='off'`) | Bypassed with a pure-data equivalent (`icatb_results_from_params.m`) that reads the same struct fields directly |
| 11 | Function handles attached to GUI option structs get saved wholesale into `.mat` files; Octave's `save()` cannot serialize function handles at all | Patched GIFT's universal `icatb_save.m` wrapper to recursively strip function handles before saving (`icatb_strip_function_handles.m`) |
| 12 | `icatb_ggmix.m`'s mixture-density normalizing constant overflows to `Inf` for shape parameters Octave's bounded solver explores (that MATLAB's apparently doesn't, for this data) | Log-space reformulation (`gammaln` + product instead of power), verified mathematically identical (~1e-17 agreement) where the original didn't overflow |
| 13 | A gamma scale parameter bounded at exactly 0 is a genuine model singularity Octave's solver steps onto more readily | Floored at `1e-10` for the density evaluation only, plus a general `Z(~isfinite(Z)) = 1e6` safety net |

## Validation run

Both engines were run on the **same real 20-subject-per-site dataset**
(`test_data/`) with identical `parameters.json` settings
(`features: ["spatial maps"]`, `run_mancova: true`,
`run_univariate_tests: false`, `numOfPCs: [5,5,5]`), producing 53 real
GIG-ICA components per site with real computed statistics -- no synthetic
data, no mocking.

Comparison methodology (not a naive flattened-array diff, since ICA/MANCOVA
results are only meaningfully comparable voxel-by-voxel):

- Mask agreement: **Jaccard overlap** of the absolute voxel indices each
  engine's auto-threshold step selected per component.
- Spatial maps / univariate p-values: restricted to the voxels **both**
  engines agree belong in the mask (set intersection), never raw
  positional truncation, before computing correlation/difference.
- MATLAB-Runtime output is MATLAB v7.3 (HDF5); read via `h5py` with manual
  object-reference dereferencing and a transpose correction for HDF5's
  C-order vs. MATLAB's column-major layout, since `scipy.io.loadmat`
  explicitly does not support v7.3.

### Results (53 components, site1)

| Metric | Result |
|---|---|
| Spatial map correlation (voxel-aligned, sign-agnostic) | mean = min = max = **1.0000** |
| Univariate per-voxel p-values (11,838 values compared) | mean/max abs. difference = **0.000000**; **0** significance (p<0.05) flips |
| Auto-threshold mask Jaccard overlap | mean = 0.9003, min = 0.4651 (18/53 below 0.90) |
| Multivariate p-values | mean abs. difference = 0.0527, max = 0.5067 |

**Interpretation:** the core computation -- ICA decomposition and
per-voxel univariate statistics -- is bit-for-bit equivalent between
engines. The only real divergence is in the multivariate (SVD-based) test,
and it is fully explained by, and isolated to, the auto-threshold mask fit
(`icatb_fitggmix.m`/`icatb_ggmix.m`): for the 9/53 components where both
engines' masks matched exactly, the multivariate p-value difference was
also exactly `0.000000` in every case (correlation between mask-overlap
quality and multivariate p-value divergence across all components:
-0.60). Univariate tests are unaffected because they don't depend on which
other voxels share the mask; the multivariate test does, because it
reduces jointly across all masked voxels.

## Solver tuning (`icatb_fitggmix.m`)

The mask divergence traces to `icatb_fitggmix.m`'s Gaussian+2-Gamma mixture
fit (`lsqcurvefit`), which is genuinely non-convex. A fast, isolated
harness (captures the real per-component `tmap` inputs once from a
MANCOVA-only re-run reusing existing GICA output, then re-fits them
directly -- no GICA, no NVFlare, ~35s total for both sites) was used to
check whether Octave's solver was converging properly or truncating early:
for the worst-agreement component, it converges cleanly (`EXITFLAG=3`,
149 of a 100,000-iteration budget used) to a stable residual regardless of
starting point -- i.e. a genuinely different but equally-converged local
optimum than MATLAB's solver finds for the same data, not a tuning
artifact.

Applied fix: **deterministic multi-start** -- try a small, fixed grid of 5
starting points (varying the two gamma components' shape/scale guesses)
and keep whichever converges to the lowest residual norm. Deterministic,
not random, so results stay reproducible run-to-run and across federated
sites; same model, same bounds, same tolerances, just a more robust search.

| Metric (both sites, 106 components) | Single-start (before) | Multi-start (landed) |
|---|---|---|
| Mean Jaccard overlap | 0.8883 | 0.8919 |
| Components below 0.90 overlap | 42 | 39 |
| Worst-case Jaccard | 0.4651 | 0.4651 (unchanged) |

Multi-start gives a modest, real improvement and is low-risk (bounded
runtime increase, same model), but does not close the remaining gap --
that gap looks like an inherent difference between Octave's and MATLAB's
bounded trust-region solver implementations, not something further
tuning (tolerances, starting points) resolves. Given univariate
significance is already unaffected by this divergence, further chasing
exact mask agreement was judged lower-value than the effort required.

### Follow-up attempt: log-reparametrization + wider multi-start (not landed)

Tried two further changes together, on the theory that the solver's
internal step scaling near a `[0, Inf)` bound (the gauss sigma and both
gammas' shape/scale parameters are all bounded that way) could itself be
why Octave's and MATLAB's solvers diverge: (1) fit `log(sigma)`,
`log(alpha)`, `log(beta)` instead of the raw bounded values, making the
problem effectively unconstrained for those 5 parameters, and (2) widen
the multi-start grid from 5 to 30 deterministic starting points.

| Metric (both sites, 106 components) | Single-start | 5-point multi-start (landed) | Log-reparam + 30-point multi-start |
|---|---|---|---|
| Mean Jaccard overlap | 0.8883 | **0.8919** | 0.8793 |
| Components below 0.90 overlap | 42 | **39** | 43 |
| Worst-case Jaccard | 0.4651 | 0.4651 | **0.2824** |

This made things worse on every metric, not better -- the worst case
dropped from 0.465 to 0.282. The likely reason: MATLAB's own solver is
also just a local optimizer, and its specific result isn't necessarily
the global optimum of this non-convex objective either, just *a*
particular local optimum of its own trust-region implementation. A
change that searches more thoroughly and finds a genuinely lower-residual
fit (which both changes here do, by construction) has no reason to land
on the *same* optimum MATLAB happens to find -- it's at least as likely
to converge to a third, different one, which is what happened. "Better
optimization" and "matches MATLAB's specific local optimum" are not the
same objective, and only the second one is what the Jaccard-overlap
metric actually rewards.

Not landed; kept here as a record so this specific direction isn't
retried from scratch later. The 5-point multi-start above remains the
best result found and is treated as the practical ceiling for this
divergence absent a much larger undertaking (e.g. reimplementing
MATLAB's trust-region-reflective step logic itself).

## Reproducing this validation

1. Build both engines' dev images (`./run_local_simulation.sh site1,site2`
   in this repo and in `nfc-mancova`) against identical `test_data/` and
   `parameters.json` settings.
2. Compare `test_output/simulate_job/<site>/coinstac-mancova/sm_stats/*.mat`
   between the two runs using the mask-aware methodology above (Octave's
   output is classic-format, loadable via `scipy.io.loadmat`; MCR's is
   v7.3/HDF5, read via `h5py`).
