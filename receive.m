clc;
clear;

%% PARAMETERS
fs = 48000;
fs_sdr = 1000000;

%% SDR SETUP
rx = sdrrx('Pluto');
rx.CenterFrequency = 433e6;   % Try small offsets later if needed
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = 4096;
rx.GainSource = 'Manual';
rx.Gain = 60;

fprintf('==============================\n');
fprintf('RECEIVER DEBUG MODE STARTED\n');
fprintf('==============================\n');

%% BUFFER
buffer = [];
flag = [0 1 1 1 1 1 1 0];

%% LOOP
while true

%% RECEIVE RF
data = rx();
data = double(data);

%% SIGNAL POWER CHECK
power = mean(abs(data).^2);
fprintf('Power: %.2f\n', power);

%% FM DEMOD (ROBUST)
fm = angle(data(2:end) .* conj(data(1:end-1)));
fm = [fm; fm(end)];

%% REMOVE DC
fm = fm - mean(fm);

%% SMOOTHING FILTER
fm = filtfilt(ones(1,25)/25, 1, fm);

%% BANDPASS (AFSK: 1200–2200 Hz)
[b, a] = butter(4, [800 2600]/(fs_sdr/2), 'bandpass');
fm = filtfilt(b, a, fm);

%% NORMALIZE
fm = fm / max(abs(fm) + 1e-6);

%% ADD TO BUFFER
buffer = [buffer; fm];

%% LIMIT BUFFER SIZE
if length(buffer) > fs_sdr
    buffer = buffer(end-fs_sdr+1:end);
end

%% WAIT FOR ENOUGH DATA
if length(buffer) < fs_sdr/2
    continue;
end

%% DOWNSAMPLE
audio = decimate(buffer(1:fs_sdr/2), round(fs_sdr/fs));

%% SLIDING WINDOW
buffer = buffer(fs_sdr/4:end);

%% FINAL CLEANUP
audio = audio - mean(audio);
audio = audio / max(abs(audio) + 1e-6);

%% DEBUG: VISUAL CHECK
figure(1);
plot(audio(1:200));
title('Recovered Audio');
drawnow;

%% DEBUG: LISTEN
% Uncomment to hear tones
% sound(audio, fs);

%% AFSK DEMOD
bits = afsk_demodulate(audio, fs);

%% FLAG CHECK
flag_pos = strfind(bits, flag);

if length(flag_pos) < 2
    continue;
end

%% TRY DECODE
try
    [src, dest, msg] = ax25_decode(bits);

    fprintf('\n📡 VALID PACKET RECEIVED\n');
    fprintf('FROM: %s\n', src);
    fprintf('TO  : %s\n', dest);
    fprintf('MSG : %s\n', msg);
    fprintf('==============================\n');

catch
    % ignore invalid frames
end

end
