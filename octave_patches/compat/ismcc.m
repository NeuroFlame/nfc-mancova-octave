function out = ismcc()
%% Paired with isdeployed.m in this directory -- see that file's comment.
%% MATLAB Compiler sets ismcc() true alongside isdeployed() in a compiled
%% build; GIFT's own addpath() guards check "~(ismcc || isdeployed)"
%% together, so this is forced true for the same reason.
out = true;
end
