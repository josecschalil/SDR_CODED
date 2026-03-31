clc;
clear;

fs = 48000;
fs_sdr = 480000;
freq_dev = 3000;

rx = sdrrx('Pluto');
rx.CenterFrequency = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = 4096;
rx.GainSource = 'Manual';
rx.Gain = 40;

fprintf('==============================\n');
fprintf('RECEIVER STARTED\n');
fprintf('Waiting for packets...\n');
fprintf('==============================\n');

buffer = [];
flag = [0 1 1 1 1 1 1 0];

while true


data = rx();
data = double(data);

% FM demod
phase = unwrap(angle(data));
fm = diff(phase);
fm = fm * fs_sdr/(2*pi*freq_dev);

buffer = [buffer; fm];

if length(buffer) > fs_sdr
    buffer = buffer(end-fs_sdr+1:end);
end

% Downsample
audio = downsample(buffer, fs_sdr/fs);

bits = afsk_demodulate(audio, fs);

% Detect packet
flag_pos = strfind(bits, flag);

if length(flag_pos) < 2
    continue;
end

try
    [src, dest, msg] = ax25_decode(bits);
    
    fprintf('\n📡 RECEIVED PACKET\n');
    fprintf('FROM: %s\n', src);
    fprintf('MSG : %s\n', msg);
    
    buffer = [];
    
catch
end


end
