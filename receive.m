fs = 48000;

audio = sdr_receive(5, fs, 433e6);

% Then decode
bits = afsk_demodulate(audio, fs);
[src, dest, msg] = ax25_decode(bits);

disp(msg)