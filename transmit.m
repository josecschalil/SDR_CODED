clc;
clear;

fs = 48000;

msg = 'HELLO FROM SDR';

%% AX25 + AFSK
frame = ax25_encode('N0CALL','APRS', msg);
audio = afsk_modulate(frame, fs);

% Debug audio
sound(audio, fs)
figure; plot(audio(1:2000)); title('AFSK Audio');

%% SDR PREP
fs_sdr = 1000000;

audio_up = resample(audio, fs_sdr, fs);

audio_up = audio_up / max(abs(audio_up) + 1e-6);

freq_dev = 5000;   % 🔥 increased
phase = 2*pi*freq_dev * cumsum(audio_up)/fs_sdr;
tx_signal = exp(1j*phase);

% Debug FM
figure; plot(real(tx_signal(1:2000))); title('FM Signal');

disp(['TX Power: ', num2str(mean(abs(tx_signal).^2))]);

%% SDR TX
tx = sdrtx('Pluto');
tx.CenterFrequency = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain = -5;

fprintf('==============================\n');
fprintf('TRANSMITTER STARTED\n');
fprintf('Message: %s\n', msg);
fprintf('==============================\n');

pause(1);
transmitRepeat(tx, tx_signal);
