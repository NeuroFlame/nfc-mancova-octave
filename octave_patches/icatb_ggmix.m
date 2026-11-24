function [Z, Y] = icatb_ggmix(P, XDATA)

% Both gamma components' scale parameters (P(5), P(7)) are bounded below
% by icatb_fitggmix.m's LB at exactly 0 -- but a Gamma(shape,scale)
% density is itself singular as scale->0 (a degenerate point mass), which
% made the *original* formula's amp = gamma(shape)*scale^shape divide by
% (near-)zero there too. Confirmed the hard way on real GICA tmap data:
% Octave's bounded lsqcurvefit steps onto exactly that boundary (where
% MATLAB's own solver apparently doesn't, for this data), producing
% Inf/NaN that broke its internal SVD step. Floor both scale parameters
% at a tiny epsilon purely for this density evaluation -- it keeps the
% model finite at the boundary without changing it anywhere the optimizer
% isn't already sitting on a singularity.
scaleFloor = 1e-10;
P5 = max(P(5), scaleFloor);
P7 = max(P(7), scaleFloor);

XDATA = XDATA-P(8);
xpos = XDATA; xpos(find(XDATA < 0)) = 0;
xneg = XDATA; xneg(find(XDATA >= 0)) = 0;

%% gaussian

Y(1,:) = P(1)*exp(-XDATA.^2/(2*P(2)^2))/sqrt(2*pi*P(2)^2);


%% gamma 1
% Numerically-stable rewrite of the normalizing constant. The original
% computed amp1 = gamma(P(4))*P(5)^P(4) directly, then divided by it --
% gamma(x) overflows to Inf for x > ~171.6, and P(5)^P(4) can also
% overflow/underflow on its own for large shape/scale values. Confirmed
% the hard way: fitting this to real GICA tmap data, Octave's bounded
% lsqcurvefit explores shape values large enough to hit exactly that,
% producing Inf/NaN that broke its internal SVD step ("svd: cannot take
% SVD of matrix containing Inf or NaN values"). gammaln(P(4)) (growing
% only like x*log(x)) and P(4)*log(P5) (a product, not a power) stay
% finite across the same range. Folding -log(amp1) into the same exp()
% call as the rest of the density is mathematically identical to the
% original wherever it didn't overflow, and well-behaved where it would
% have. xpos.^exponent1 is left untouched (not folded into log-space)
% specifically to preserve its exact 0^0=1 / 0^positive=0 / 0^negative=Inf
% boundary behavior at xpos==0, which the original formula already
% relied on and got right.
exponent1 = P(4)-1;

Y(2,:) = P(3)*(xpos.^exponent1).*exp(-xpos/P5 - gammaln(P(4)) - P(4)*log(P5));

%% gamma 2
exponent2 = P(6)-1;
Probgamma2 = max(1-P(1)-P(3), 0);
Y(3,:) = Probgamma2*((-xneg).^exponent2).*exp(xneg/P7 - gammaln(P(6)) - P(6)*log(P7));

%Y(3,:) = P(6)*((-xneg).^P(7)).*exp(xneg/P(8));

Z = sum(Y,1);

% General safety net, on top of the two specific fixes above: this model
% is evaluated across 7 different real tmaps (one per
% comp_network_names network) in the real pipeline, each with its own
% data-dependent shape -- and each has turned up its own way to drive a
% term briefly non-finite during the solver's exploration (gamma()
% overflow; a scale parameter at its singular lower bound; possibly
% others not yet hit). Rather than chase every individual cause as a new
% real dataset happens to trigger it, clamp any remaining non-finite
% output to a large-but-finite residual here. This only ever engages
% where the model was already mathematically singular/overflowing (never
% in the well-behaved region the two fixes above don't already cover), so
% it does not change the fit anywhere it was otherwise well-defined -- it
% just gives the solver a large penalty to step away from instead of a
% non-finite value that kills its internal SVD outright.
Z(~isfinite(Z)) = 1e6;
