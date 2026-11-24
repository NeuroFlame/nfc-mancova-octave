function [results, inputParameters] = icatb_results_from_params(inputParameters)
%% Pure-data equivalent of icatb_OptionsWindow.m's internal
%% results_from_controls/uiOptionsCallback, for use when the dialog is
%% always built with visible='off' and nothing is ever interactively
%% changed (true for every call site in this batch pipeline). Reads each
%% option straight from its own .value/.answerString/.answerType fields
%% -- exactly what results_from_controls would read back off the
%% never-shown, never-modified uicontrol widgets anyway, since those
%% widgets are themselves constructed from these same fields -- instead
%% of building real GUI widgets and reading their live state back.
%%
%% That real path hit three separate Octave/uicontrol incompatibilities
%% in icatb_OptionsWindow.m (uicontrol 'frame' style unimplemented,
%% textwrap undefined, and a fatal one: for a popup/listbox control whose
%% 'String' was set from a multi-row char matrix, Octave's
%% get(h,'string') did not round-trip the same multi-row shape MATLAB's
%% does, so indexing it by the selected row ("getString(2,_): out of
%% bound 1 (dimensions are 1x7)") failed) -- for a dialog nobody ever
%% sees, none of which is worth chasing when the inputs are already known.
results = struct;
for ii = 1:length(inputParameters)
    for jj = 1:length(inputParameters(ii).options)
        % Several options carry a .callback function handle (e.g.
        % @selectMaskCallback) for the real dialog's interactive click
        % handling, which never fires here. Worse, downstream code saves
        % the whole inputParameters/mancovanInfo struct to a .mat file,
        % and Octave's save() cannot serialize a function handle
        % ("save: wrong type argument 'function handle'") -- strip it.
        if isfield(inputParameters(ii).options(jj), 'callback')
            inputParameters(ii).options(jj).callback = [];
        end
        opt = inputParameters(ii).options(jj);
        objectTag = opt.tag;
        if isempty(objectTag)
            error('Set the tags for the objects on the frame');
        end
        uiType = lower(opt.uiType);
        if strcmp(uiType, 'edit')
            returnedString = deblank(opt.answerString);
        elseif strcmp(uiType, 'listbox') || ~isempty(strfind(uiType, 'popup'))
            answerStrings = opt.answerString;
            idx = opt.value;
            if ischar(answerStrings)
                returnedString = deblank(answerStrings(idx, :));
            else
                returnedString = deblank(answerStrings{idx});
            end
        elseif strcmp(uiType, 'checkbox') || strcmp(uiType, 'radiobutton')
            returnedString = num2str(opt.value);
        else
            returnedString = deblank(opt.answerString);
        end
        if strcmpi(opt.answerType, 'numeric')
            returnedString = str2num(returnedString);
        end
        results = setfield(results, objectTag, returnedString);
        if isfield(opt, 'userdata') && ~isempty(opt.userdata)
            results = setfield(results, [objectTag, '_userdata'], opt.userdata);
        end
    end
end
end
