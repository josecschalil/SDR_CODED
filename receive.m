clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

%% LPF
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

%% SDR setup
rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;
rx.GainSource         = 'Manual';
rx.Gain               = 20;        % starting gain — AGC will adjust from here

% AGC parameters
POWER_TARGET = 30;
POWER_MIN    = 20;
POWER_MAX    = 45;
GAIN_MIN     = 0;
GAIN_MAX     = 60;
gain_current = 20;

fprintf('==============================\n');
fprintf('RECEIVER ACTIVE — 433 MHz\n');
fprintf('AGC enabled — target power: %d\n', POWER_TARGET);
fprintf('==============================\n');

while true
    %% 1 — RECEIVE
    %% 1 — RECEIVE (grab two frames and stitch)
    %% 1 — RECEIVE (3 frames to guarantee full transmission is captured)
data1 = rx();
data2 = rx();
data3 = rx();
data  = double([data1; data2; data3]);   % 3 seconds — TX loop is 2s so full frame always inside
power = mean(abs(data).^2);  % 2 seconds of signal
  
  

    %% 2 — AGC: adjust gain based on received power
    %% 2 — AGC
if power > 1.0
    if power > POWER_MAX || power < POWER_MIN
        % Proportional step — smaller correction near target
        error_db  = 10 * log10(POWER_TARGET / max(power, 0.01));
        gain_step = round(error_db * 0.5);          % 0.5 = damping factor
        gain_step = max(-5, min(5, gain_step));      % clamp to ±5 dB per step
        gain_new  = gain_current + gain_step;
        gain_new  = max(GAIN_MIN, min(GAIN_MAX, gain_new));

        if gain_new ~= gain_current
            gain_current = gain_new;
            rx.Gain      = gain_current;
            fprintf('Power: %6.1f  AGC → %d dB\n', power, gain_current);
            continue;
        end
    end
end

    fprintf('Power: %6.2f  Gain: %d dB  ', power, gain_current);

    if power < 1.0
        fprintf('(no signal)\n');
        continue;
    end
    fprintf('(signal — decoding)\n');

    %% 3 — FM DEMODULATE
    fm = angle(data(2:end) .* conj(data(1:end-1)));
    fm = [fm; fm(end)];
    fm = fm * (fs_sdr / (2*pi*dev));

    %% 4 — LPF + DECIMATE
    fm_f  = filter(lpf, fm);
    audio = fm_f(1:decim:end);

    %% 5 — NORMALISE
    audio = audio - mean(audio);
    peak  = max(abs(audio));
    if peak < 1e-4
        fprintf('  audio too quiet — skipping\n');
        continue;
    end
    audio = audio / peak;



    %% 7 — AFSK DEMODULATE
    bits = afsk_demodulate(audio, fs);
    if isempty(bits)
        fprintf('  afsk_demodulate empty\n');
        continue;
    end

    %% 8 — AX.25 DECODE
    try
        [src, dest, msg] = ax25_decode(bits);
        fprintf('\n==============================\n');
        fprintf('  MESSAGE RECEIVED\n');
        fprintf('  FROM : %s\n', src);
        fprintf('  TO   : %s\n', dest);
        fprintf('  MSG  : %s\n', msg);
        fprintf('  GAIN : %d dB\n', gain_current);
        fprintf('==============================\n\n');
    catch e
        fprintf('  decode failed: %s\n', e.message);
    end
end