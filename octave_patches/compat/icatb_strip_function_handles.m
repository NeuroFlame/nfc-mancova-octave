function out = icatb_strip_function_handles(in)
%% Octave's save() cannot serialize a function handle at all
%% ("save: wrong type argument 'function handle'") -- unlike MATLAB,
%% which can. GIFT's GUI-construction code (icatb_mancovan_feature_options.m
%% and friends) attaches real function handles as callbacks on option
%% structs purely for interactive click handling in the real dialog,
%% which this headless batch pipeline never shows or touches -- but
%% icatb_save.m (see its patched copy) then saves those same structs to
%% disk wholesale. Recursively replace any function handle with [] before
%% saving; nothing reads a callback field back after the (never shown)
%% dialog closes.
if isa(in, 'function_handle')
    out = [];
elseif isstruct(in)
    out = in;
    fn = fieldnames(in);
    for i = 1:numel(in)
        for f = 1:numel(fn)
            out(i).(fn{f}) = icatb_strip_function_handles(in(i).(fn{f}));
        end
    end
elseif iscell(in)
    out = cell(size(in));
    for i = 1:numel(in)
        out{i} = icatb_strip_function_handles(in{i});
    end
else
    out = in;
end
end
