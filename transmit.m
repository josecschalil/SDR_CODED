clc;
clear;

fs = 48000;

msg = 'HELLO FROM SDR';

frame = ax25_encode('N0CALL','APRS', msg);
audio = afsk_modulate(frame, fs);

%% SDR PREP
fs_sdr = 1000000;

audio_up = resample(audio, fs_sdr, fs);

freq_dev = 3000;
phase = 2*pi*freq_dev * cumsum(audio_up)/fs_sdr;
tx_signal = exp(1j*phase);

%% SDR TX
tx = sdrtx('Pluto');
tx.CenterFrequency = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain = 0;

fprintf('==============================\n');
fprintf('TRANSMITTER STARTED\n');
fprintf('Message: %s\n', msg);
fprintf('==============================\n');

transmitRepeat(tx, tx_signal);
