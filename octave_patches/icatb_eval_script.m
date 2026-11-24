function inputData = icatb_eval_script(file_name)
%% Evaluate script and store the variables in a data structure
%
% Inputs:
% file_name - File name
%
% Outputs:
% inputData - Input data structure
%

if (isdeployed)
    % execute scripts differently in deployed mode
	fid = -1;
	try
		fid = fopen(file_name, 'r');
	catch
	end
    
    if (fid == -1)
		try
			tmp_strs = file_name;			
		catch
			error(['File ', file_name, ' cannot be opened']);
		end
	else
		try
			tmp_strs = fread(fid, '*char');
			fclose(fid);
		catch
			fclose(fid);
		end
		
    end
    
    
    eval(tmp_strs');
    
    clear fid tmp_strs;
    
else

    %% Evaluate file by path directly. The previous approach -- cd to the
    %% file's directory and eval() its bare name without an extension --
    %% breaks for any filename containing a character that isn't valid in
    %% an unquoted MATLAB/Octave expression (e.g. a hyphen, which eval()
    %% parses as subtraction between two undefined identifiers). run()
    %% executes a script by its full path and handles this correctly
    %% regardless of filename.
    run(file_name);

end

if (nargout == 1)
    
    vars = whos;
    
    if (length(vars) == 1)
        error(['No variables found in file ', file_name]);
    end
    
    % Generate inputData
    inputData = struct;
    for n = 1:length(vars)
        inputData = setfield(inputData, vars(n).name, eval(vars(n).name));
    end
    
end