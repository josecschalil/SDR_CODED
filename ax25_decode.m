function [src, dest, message] = ax25_decode(nrzi_bits)
% AX.25 Decoder
% Input:
%   bitstream - binary array (0/1)
%
% Outputs:
%   src     - source callsign
%   dest    - destination callsign
%   message - decoded text message

%% 1. Find flags (0x7E → 01111110)
bitstream = nrzi_decode(nrzi_bits);
flag = [0 1 1 1 1 1 1 0];

% Find start flag
start_idx = strfind(bitstream, flag);
if length(start_idx) < 2
    error('Not enough flags found');
end

% Extract payload between first two flags
payload_bits = bitstream(start_idx(1)+8 : start_idx(2)-1);

%% 2. Remove bit stuffing
unstuffed = [];
count = 0;

i = 1;
while i <= length(payload_bits)
    unstuffed = [unstuffed payload_bits(i)];
    
    if payload_bits(i) == 1
        count = count + 1;
        if count == 5
            % skip next stuffed 0
            i = i + 1;
            count = 0;
        end
    else
        count = 0;
    end
    
    i = i + 1;
end

%% 3. Convert bits → bytes (LSB first)
num_bytes = floor(length(unstuffed)/8);
bytes = zeros(1, num_bytes, 'uint8');

for i = 1:num_bytes
    b = unstuffed((i-1)*8 + (1:8));
    bytes(i) = bi2de(b, 'right-msb');
end

%% 4. Extract FCS
data = bytes(1:end-2);
recv_fcs = uint16(bytes(end-1)) + bitshift(uint16(bytes(end)),8);

calc_fcs = crc_ccitt(data);

if recv_fcs ~= calc_fcs
    error('FCS check FAILED');
end

%% 5. Decode addresses
% Address structure:
% dest (7 bytes) + src (7 bytes)

dest_bytes = data(1:7);
src_bytes  = data(8:14);

dest = decode_callsign(dest_bytes);
src  = decode_callsign(src_bytes);

%% 6. Extract INFO field
% Skip: 14 addr + CTRL + PID
CTRL_idx = 15;
PID_idx  = 16;

info = data(17:end);

message = char(info);

end


%% -------- Helper Functions --------

function callsign = decode_callsign(addr_bytes)

chars = char(bitshift(addr_bytes(1:6), -1));
callsign = strtrim(chars);

end


function fcs = crc_ccitt(data)

poly = hex2dec('1021');
fcs = uint16(hex2dec('FFFF'));

for i = 1:length(data)
    fcs = bitxor(fcs, bitshift(uint16(data(i)),8));
    
    for j = 1:8
        if bitand(fcs, hex2dec('8000'))
            fcs = bitxor(bitshift(fcs,1), poly);
        else
            fcs = bitshift(fcs,1);
        end
        fcs = bitand(fcs, hex2dec('FFFF'));
    end
end

% Final XOR
fcs = bitxor(fcs, hex2dec('FFFF'));

end