function out = str2mat(varargin)
%% str2mat is a legacy MATLAB function GIFT still calls, which Octave never
%% implemented (see https://www.octave.org/missing.html). It behaves the
%% same as strvcat, which Octave does implement -- forward to it.
out = strvcat(varargin{:});
end
