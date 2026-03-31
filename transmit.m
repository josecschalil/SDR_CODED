clc; clear;

fs     = 48000;
fs_sdr = 960000;
dev    = 5000;
msg    = 'HELLO FROM SDR';

%% STEP 1 — AX.25 encode (produces stuffed + NRZI bits)
frame = ax25_encode('N0CALL', 'APRS', msg);
fprintf('Frame bits: %d\n', length(frame));

%% STEP 2 — AFSK modulate (frame already has NRZI from ax25_encode)
audio = afsk_modulate(frame, fs);
fprintf('Audio: %d samples (%.2f sec)\n', length(audio), length(audio)/fs);

%% STEP 3 — Upsample
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);

%% STEP 4 — FM modulate
phase     = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

% Verify deviation
inst_freq = diff(unwrap(angle(tx_signal))) / (2*pi) * fs_sdr;
fprintf('FM dev check: %.0f Hz (should be ~%d)\n', max(abs(inst_freq)), dev);

%% STEP 5 — Pad with carrier (1 sec each side — generous for RX capture window)
n_pad    = round(1.0 * fs_sdr);
carrier  = zeros(n_pad, 1);          % silent carrier padding
tx_final = [carrier; tx_signal(:); carrier];

%% STEP 6 — Transmit
tx = sdrtx('Pluto');
tx.CenterFrequency    = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain               = -10;

fprintf('==============================\n');
fprintf('TRANSMITTING — will loop for 60 seconds\n');
fprintf('Run diagnose.m or rx_sdr.m NOW\n');
fprintf('==============================\n');

% transmitRepeat is non-blocking — tx object must stay alive
% Keep script running so tx object is not destroyed
transmitRepeat(tx, tx_final);

% Hold transmission alive for 60 seconds
% Increase this number if you need more time
t_start = tic;
while toc(t_start) < 60
    fprintf('TX alive — %.0f sec remaining\n', 60 - toc(t_start));
    pause(5);
end

fprintf('TX done — releasing\n');
release(tx);