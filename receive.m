clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

MY_CALL = 'N0ACK';     % This receiver's callsign — must match ACK_CALL in tx_sdr
DEST    = 'APRS';

%% LPF
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

%% AGC state
POWER_TARGET = 30;
POWER_MIN    = 20;
POWER_MAX    = 45;
GAIN_MIN     = 0;
GAIN_MAX     = 60;
gain_current = 20;

%% RX setup
rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;
rx.GainSource         = 'Manual';
rx.Gain               = gain_current;

%% TX setup (for sending ACK)
tx = sdrtx('Pluto');
tx.CenterFrequency    = 433e6;
tx.BasebandSampleRate = fs_sdr;
tx.Gain               = -10;

fprintf('==============================\n');
fprintf('RECEIVER ACTIVE — %s\n', MY_CALL);
fprintf('Will ACK every decoded message\n');
fprintf('==============================\n');

while true
    %% Receive 3 frames
    data1 = rx(); data2 = rx(); data3 = rx();
    data  = double([data1; data2; data3]);
    power = mean(abs(data).^2);

    %% AGC
    if power > 1.0
        if power > POWER_MAX || power < POWER_MIN
            error_db     = 10 * log10(POWER_TARGET / max(power, 0.01));
            gain_step    = max(-5, min(5, round(error_db * 0.5)));
            gain_new     = max(GAIN_MIN, min(GAIN_MAX, gain_current + gain_step));
            if gain_new ~= gain_current
                gain_current = gain_new;
                rx.Gain      = gain_current;
                fprintf('Power: %.1f  AGC → %d dB\n', power, gain_current);
                continue;
            end
        end
    end

    fprintf('Power: %.2f  Gain: %d dB  ', power, gain_current);

    if power < 1.0
        fprintf('(no signal)\n');
        continue;
    end
    fprintf('(decoding)\n');

    %% FM demod
    fm    = angle(data(2:end) .* conj(data(1:end-1)));
    fm    = [fm; fm(end)];
    fm    = fm * (fs_sdr / (2*pi*dev));
    fm_f  = filter(lpf, fm);
    audio = fm_f(1:decim:end);
    audio = audio - mean(audio);
    peak  = max(abs(audio));
    if peak < 1e-4, fprintf('  too quiet\n'); continue; end
    audio = audio / peak;

    %% Demodulate + decode
    bits = afsk_demodulate(audio, fs);
    if isempty(bits), continue; end

    try
        [src, dest, msg] = ax25_decode(bits);

        fprintf('\n==============================\n');
        fprintf('  MESSAGE RECEIVED\n');
        fprintf('  FROM : %s\n', src);
        fprintf('  TO   : %s\n', dest);
        fprintf('  MSG  : %s\n', msg);
        fprintf('==============================\n\n');

        %% Send ACK back
        fprintf('Sending ACK to %s...\n', src);

        ack_text  = sprintf('ACK:%s', msg(1:min(8,end)));  % echo first 8 chars
        ack_frame = ax25_encode(MY_CALL, src, ack_text);
        ack_audio = afsk_modulate(ack_frame, fs);
        ack_up    = resample(ack_audio, fs_sdr, fs);
        ack_up    = ack_up / (max(abs(ack_up)) + 1e-6);
        ack_phase = 2*pi*dev * cumsum(ack_up) / fs_sdr;
        ack_iq    = exp(1j * ack_phase);

        % Pad ACK to 2 seconds
        total_s   = 2 * fs_sdr;
        pad_e     = floor((total_s - length(ack_iq)) / 2);
        pad_e     = max(pad_e, round(0.2*fs_sdr));
        ack_pad   = [zeros(pad_e,1); ack_iq(:); zeros(pad_e,1)];
        if length(ack_pad) > total_s
            ack_pad = ack_pad(1:total_s);
        else
            ack_pad = [ack_pad; zeros(total_s-length(ack_pad),1)];
        end

        % Pause RX, transmit ACK, resume RX
        release(rx);
        pause(0.1);
        transmitRepeat(tx, ack_pad);
        pause(2.5);      % transmit for 2.5 seconds (> one TX loop on other side)
        release(tx);
        pause(0.1);

        % Restart RX
        rx = sdrrx('Pluto');
        rx.CenterFrequency    = 433e6;
        rx.BasebandSampleRate = fs_sdr;
        rx.SamplesPerFrame    = fs_sdr;
        rx.GainSource         = 'Manual';
        rx.Gain               = gain_current;

        fprintf('ACK sent — resuming receive\n\n');

    catch e
        fprintf('  decode failed: %s\n', e.message);
    end
end
