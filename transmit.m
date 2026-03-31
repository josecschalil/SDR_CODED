clc; clear;

fs     = 48000;
fs_sdr = 960000;   % MUST match RX exactly — 960k/48k = 20 (integer)
dev    = 5000;     % FM deviation in Hz — MUST match RX demod scaling

msg = 'HELLO FROM SDR';

%% STEP 1 — Build AX.25 + NRZI + AFSK
frame = ax25_encode('N0CALL', 'APRS', msg);
audio = afsk_modulate(frame, fs);

% Sanity check — should sound like modem chirp
fprintf('Audio length: %d samples (%.2f sec)\n', length(audio), length(audio)/fs);
sound(audio, fs);
figure(1); plot(audio(1:min(2000,end))); title('AFSK audio (baseband)'); drawnow;

%% STEP 2 — Upsample to SDR rate
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);

%% STEP 3 — FM modulate (manual IQ — matches what RX angle() demod expects)
phase    = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

% Verify FM deviation is correct — instantaneous freq should swing ±dev Hz
inst_freq = diff(unwrap(angle(tx_signal))) / (2*pi) * fs_sdr;
fprintf('FM deviation check — max inst freq: %.0f Hz (should be ~%.0f)\n', ...
        max(abs(inst_freq)), dev);

figure(2); plot(real(tx_signal(1:2000))); title('FM IQ signal (real part)'); drawnow;
fprintf('TX power: %.4f\n', mean(abs(tx_signal).^2));

%% STEP 4 — Repeat transmit with padding
% Pad with 0.5s of carrier before and after so RX has time to lock
n_pad    = round(0.5 * fs_sdr);
carrier  = exp(1j * zeros(n_pad, 1));   % unmodulated carrier = silence padding
tx_final = [carrier; tx_signal; carrier];

%% STEP 5 — Send
tx = sdrtx('Pluto');
tx.CenterFrequency    = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain               = -10;   % start conservative, increase if needed

fprintf('==============================\n');
fprintf('TRANSMITTER STARTED\n');
fprintf('Freq  : 433 MHz\n');
fprintf('Dev   : %d Hz\n', dev);
fprintf('Msg   : %s\n', msg);
fprintf('==============================\n');

pause(1);
transmitRepeat(tx, tx_final);