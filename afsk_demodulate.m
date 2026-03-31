function bitstream = afsk_demodulate(audio, fs)

audio = audio(:);
audio = audio / (max(abs(audio)) + 1e-6);
% Strip leading and trailing near-zero sections (carrier padding)
% This prevents the matched filter from wasting time on silent regions
threshold = 0.05;
active    = find(abs(audio) > threshold);
if length(active) < 100
    bitstream = [];
    return;
end
audio = audio(active(1):active(end));
Rb  = 1200;
Ns  = round(fs / Rb);   % 40 samples per symbol
fs  = Rb * Ns;          % enforce exact rate

f_mark  = 1200;
f_space = 2200;

%% Step 1 — matched filter approach instead of block Goertzel
% Correlate with reference tones over a sliding 1-symbol window
n  = (0:Ns-1)';
ref_mark  = exp( 1j*2*pi*f_mark /fs*n);
ref_space = exp( 1j*2*pi*f_space/fs*n);

% Compute energy at each sample via sliding correlation
E_mark  = abs(conv(audio, conj(flipud(ref_mark )), 'same')).^2;
E_space = abs(conv(audio, conj(flipud(ref_space)), 'same')).^2;

% Decision signal: +1 where mark dominates, -1 where space dominates
decision = double(E_mark > E_space);

%% Step 2 — symbol timing recovery
% Find the best sampling offset by maximising decision confidence
% (largest average energy difference at sampling instants)
best_bits  = [];
best_score = -inf;

for offset = 1:Ns
    sample_idx = offset:Ns:length(decision);
    if isempty(sample_idx), continue; end

    sampled_mark  = E_mark(sample_idx);
    sampled_space = E_space(sample_idx);
    margin = sampled_mark - sampled_space;

    % Score = mean absolute margin (high = confident decisions)
    score = mean(abs(margin));

    if score > best_score
        best_score = score;
        best_bits  = double(margin > 0);
    end
end

bitstream = best_bits(:)';
end