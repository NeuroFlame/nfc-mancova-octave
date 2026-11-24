function out = isdeployed()
%% GIFT guards several MATLAB-only/interactive code paths (publish() calls,
%% GUI dialogs, the icatb_eval_script.m batch-file loader) behind
%% `if (isdeployed) ... else ... end`, taking the "else" branch only under
%% desktop/interactive MATLAB. Under the real MATLAB-Compiler/MCR build
%% isdeployed() is always true, so those branches never run there. Octave
%% has no concept of a "deployed" build and its own isdeployed() always
%% returns false -- but running headless, script-driven batch jobs under
%% Octave is functionally the same situation GIFT means by "deployed", and
%% forcing it true here is what actually fixes two confirmed bugs: the
%% icatb_eval_script.m non-deployed branch breaking on hyphenated batch
%% filenames (see icatb_eval_script.m's own patched copy), and
%% icatb_report_generator.m calling publish() on a function file, which
%% Octave's publish() rejects ("only script files can be published").
out = true;
end
