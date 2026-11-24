function [tapers, eigvals] = icatb_dpss(N, NW, K)
%% Direct discrete prolate spheroidal sequence (DPSS/Slepian taper)
%% computation, standing in for GIFT's own icatb_dpss.p (MATLAB p-code,
%% unreadable by Octave) and for Octave's own `signal` package dpss(),
%% which is a documented-but-unimplemented stub as of octave-signal 1.4.3
%% ("belongs to the signal package ... but has not yet been implemented").
%%
%% Standard construction (Percival & Walden, "Spectral Analysis for
%% Physical Applications", sec. 6.3): the tapers are the eigenvectors of
%% the symmetric tridiagonal matrix below, which is the well-conditioned
%% way to compute them (vs. the dense sinc-kernel "concentration" matrix).
%% This is the same construction MATLAB's own dpss ultimately relies on.
%%
%% Only the taper waveforms are returned meaningfully here -- confirmed by
%% reading icatb_mtspectrumc.m (the only caller, via icatb_dpsschk.m): it
%% never uses the second (eigenvalue) return value, so no adaptive
%% weighting depends on getting that normalization convention exactly
%% right. eigvals is still returned (as the tridiagonal matrix's own
%% eigenvalues, sorted descending) for interface compatibility, but is not
%% the [0,1] "concentration ratio" MATLAB's dpss returns.
W = NW / N;
i = (0:N-1)';
d = ((N - 1) / 2 - i) .^ 2 * cos(2 * pi * W);
k = (1:N - 1)';
e = k .* (N - k) / 2;
T = diag(d) + diag(e, 1) + diag(e, -1);
[V, D] = eig(T);
evals = diag(D);
[~, idx] = sort(evals, 'descend');
idx = idx(1:K);
V = V(:, idx);

for c = 1:K
    if mod(c, 2) == 1
        if sum(V(:, c)) < 0
            V(:, c) = -V(:, c);
        end
    else
        mid = ceil(N / 2);
        if V(mid + 1, c) - V(mid, c) < 0
            V(:, c) = -V(:, c);
        end
    end
    V(:, c) = V(:, c) / norm(V(:, c));
end

tapers = V;
eigvals = evals(idx);
end
