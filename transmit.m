clc; clear;

fs     = 48000;
fs_sdr = 960000;
dev    = 5000;
msg    = 'HELLO FROM SDR';

%% STEP 1 — AX.25 encode
frame = ax25_encode('N0CALL', 'APRS', msg);
fprintf('Frame bits: %d\n', length(frame));

%% STEP 2 — AFSK modulate
audio = afsk_modulate(frame, fs);
fprintf('Audio: %d samples (%.3f sec)\n', length(audio), length(audio)/fs);

%% STEP 3 — Upsample
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);

%% STEP 4 — FM modulate
phase     = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

% Verify deviation
inst_freq = diff(unwrap(angle(tx_signal))) / (2*pi) * fs_sdr;
fprintf('FM dev check: %.0f Hz (should be ~%d)\n', max(abs(inst_freq)), dev);

%% STEP 5 — Pad to exactly 2 seconds
% RX grabs 2-second frames — TX loop must be exactly 2 seconds
% so every RX capture contains exactly one complete transmission
total_samples = 2 * fs_sdr;                              % 2.000 sec exactly
signal_len    = length(tx_signal);

if signal_len >= total_samples
    % Signal longer than 2s (shouldn't happen for short messages)
    warning('Signal longer than 2s — increase total_samples');
    tx_final = tx_signal(1:total_samples);
else
    % Distribute remaining space equally before and after signal
    pad_each  = floor((total_samples - signal_len) / 2);
    pad_each  = max(pad_each, round(0.2 * fs_sdr));      % minimum 0.2s each side
    carrier   = zeros(pad_each, 1);
    tx_padded = [carrier; tx_signal(:); carrier];

    % Trim or zero-extend to hit exactly total_samples
    if length(tx_padded) > total_samples
        tx_final = tx_padded(1:total_samples);
    else
        tx_final = [tx_padded; zeros(total_samples - length(tx_padded), 1)];
    end
end

fprintf('TX frame: %d samples = %.4f sec\n', length(tx_final), length(tx_final)/fs_sdr);
fprintf('Signal occupies %.1f%% of frame\n', signal_len/total_samples*100);

%% STEP 6 — Send
tx = sdrtx('Pluto');
tx.CenterFrequency    = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain               = -2;

fprintf('==============================\n');
fprintf('TRANSMITTING — looping for 60 sec\n');
fprintf('RX capture window = 2 sec = TX loop length\n');
fprintf('Run rx_sdr.m NOW\n');
fprintf('==============================\n');

transmitRepeat(tx, tx_final);

t_start = tic;
while toc(t_start) < 60
    fprintf('TX alive — %.0f sec remaining\n', 60 - toc(t_start));
    pause(5);
end

fprintf('TX done — releasing\n');
release(tx);