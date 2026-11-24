function [y, cutoff, PF, P0, FH] = icatb_fitggmix(meanmap, nstd)
%[y, cutoff, PF, P0, FH] = fitggmix(meanmap, nstd)
[N,X] = hist(meanmap,800);


XDATA = X;
YDATA = N;
area = trapz(XDATA,YDATA);
YDATA = YDATA/area;

opts_cell = {'TolFun',1e-14, 'TolX', 1e-14, 'MaxFunEvals', 100000, 'Display', 'off'};
options = optimset(opts_cell{:});

sigma = std(meanmap);

beta = std(meanmap)*.4;
alpha = 5;
[mv, ind]=max(YDATA);
offset = XDATA(ind);

LB = [0.5                      0          0                 0             0          0                  0     -0.5*sigma];
UB = [1                       Inf         0.5             Inf           Inf         Inf                Inf     0.5*sigma];

% Multi-start: this Gaussian+2-Gamma mixture fit is genuinely non-convex;
% a single starting point can converge to a different local optimum than
% whatever MATLAB's own solver happens to find on the same data. Confirmed
% on real GICA tmap data: Octave's solver converges cleanly (within its
% iteration budget, not truncated) but to a different basin than MATLAB's
% for some components -- this is the one remaining, well-isolated source
% of divergence between the Octave and MCR pipelines (confirmed to only
% ever affect the auto-threshold voxel mask; per-voxel univariate stats
% are identical either way, see nfc-mancova-octave validation notes). Try
% a small, deterministic (not random -- keeps results reproducible run to
% run and across federated sites) grid of shape/scale starting points for
% both gamma components and keep whichever converges to the lowest
% residual norm. Same model, same bounds, same tolerances -- just a more
% robust search over the same non-convex objective.
alpha_candidates     = [5,  1,  15, 5,    5];
beta_mult_candidates  = [1,  1,  1,  0.25, 4];

bestRESNORM = Inf;
PF = []; P0 = []; RESNORM = []; RESIDUAL = []; EXITFLAG = []; OUTPUT = [];

for k = 1:numel(alpha_candidates)
    alpha_k = alpha_candidates(k);
    beta_k = beta * beta_mult_candidates(k);
    P0_k = [0.8, sigma, .1, alpha_k, beta_k, alpha_k, beta_k, offset];
    try
        [PF_k,RESNORM_k,RESIDUAL_k,EXITFLAG_k,OUTPUT_k] = lsqcurvefit(@icatb_ggmix,P0_k,XDATA,YDATA, LB, UB, options);
    catch
        opts2 = {'TolFun',1e-14, 'TolX', 1e-14, 'MaxFunEvals', 100000, 'Display', 'off', 'Jacobian', 'off'};
        opts2 = optimset(opts2{:});
        [PF_k,RESNORM_k,RESIDUAL_k,EXITFLAG_k,OUTPUT_k] = icatb_lsqcurvefit(@icatb_ggmix,P0_k,XDATA,YDATA, LB, UB, opts2);
    end
    if (isfinite(RESNORM_k) && RESNORM_k < bestRESNORM)
        bestRESNORM = RESNORM_k;
        PF = PF_k; P0 = P0_k; RESNORM = RESNORM_k;
        RESIDUAL = RESIDUAL_k; EXITFLAG = EXITFLAG_k; OUTPUT = OUTPUT_k;
    end
end

%[PF,RESNORM,RESIDUAL,EXITFLAG,OUTPUT] = lsqcurvefit(@ggmix,P0,XDATA,YDATA, [],[], options);

%% plotting
%x = linspace(-max(abs(XDATA)), max(abs(XDATA)), 1000);
x = linspace(-8*PF(2), 8*PF(2), 2000);
[z, y]=icatb_ggmix(PF,x);
FH = figure; set(FH, 'Color', [0 0 0])
plot(XDATA,YDATA, 'Color', [.8 .8 .8], 'LineWidth', 1);
hold on;
plot(x,y(1,:), 'c',  x,y(2,:), 'g',  x,y(3,:), 'y')
plot(x,z,'r')
L = legend('data', 'gaussian', 'gamma_+', 'gamma_-', 'fit');
set(L, 'Color', [0 0 0], 'TextColor', [1 1 1])
axis tight;
ax = axis;
axis([min(x) max(x) 0 ax(4)])
H = gca;
set(H, 'Color', [0 0 0], 'XColor', [1 1 1], 'YColor', [1 1 1]);
set(get(H, 'XLabel'), 'String','voxel value', 'FontName', 'Arial', 'FontSize', 12);
set(get(H, 'YLabel'), 'String','frequency', 'FontName', 'Arial', 'FontSize', 12);
set(H, 'FontName', 'Arial', 'FontSize', 10);
titstring = sprintf('cutoff: %d std, mu = %0.3f, sigma = %0.3f', nstd, PF(8), PF(2));
set(get(H, 'Title'), 'String', titstring, 'Color', [1 1 1],'FontName', 'Arial', 'FontSize', 12);

%axis([-2 2 0 ax(4)])

cutoff(1) = PF(8)-nstd*PF(2);
cutoff(2) = PF(8)+nstd*PF(2);

hold on
plot([cutoff(1) cutoff(1)], [0, max(YDATA)], 'm--')
plot([cutoff(2) cutoff(2)], [0, max(YDATA)], 'm--')

PF = param_to_struct(PF);
P0 = param_to_struct(P0);


function S = param_to_struct(P)
S.gauss_a = P(1);
S.gauss_mu = P(8);
S.gauss_sigma = P(2);
S.gamma1_a = P(3);
S.gamma1_alpha = P(4);
S.gamma1_beta = P(5);
S.gamma2_a = 1-P(1)-P(3);
S.gamma2_alpha = P(6);
S.gamma2_beta = P(7);
