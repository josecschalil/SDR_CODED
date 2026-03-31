fs = 48000;

frame = ax25_encode('N0CALL','APRS','HELLO');
audio = afsk_modulate(frame, fs);

sdr_transmit(audio, fs, 433e6);