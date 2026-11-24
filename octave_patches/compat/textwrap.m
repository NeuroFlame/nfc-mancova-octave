function [outstring, position] = textwrap(h, instring, varargin)
%% textwrap is documented as missing in Octave
%% (https://www.octave.org/missing.html). GIFT's only use of it
%% (icatb_OptionsWindow.m) is to size a text label within a GUI dialog
%% that is always built with visible='off' in this batch pipeline --
%% nothing is ever rendered to a screen, and the wrapped text/position
%% only feed cosmetic widget layout, not icatb_OptionsWindow's actual
%% return values (inputParameters/results), which is all that's used
%% downstream. Pass the text through unwrapped and reuse the control's
%% own existing position as a reasonable extent.
outstring = instring;
position = get(h, 'Position');
end
