clc;
clear;

fs = 48000;

msg = 'HELLO FROM SDR';

frame = ax25_encode('N0CALL','APRS', msg);
audio = afsk_modulate(frame, fs);

% Convert to SDR signal
fs_sdr = 480000;
interp_factor = fs_sdr/fs;
audio_up = interp(audio, interp_factor);

freq_dev = 3000;
phase = 2*pi*freq_dev * cumsum(audio_up)/fs_sdr;
tx_signal = exp(1j*phase);

tx = sdrtx('Pluto');
tx.CenterFrequency = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain = 0;

disp('Transmitting continuously...');
transmitRepeat(tx, tx_signal);
