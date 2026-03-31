function radios = plutoDiscoverRadios()
% Discover connected Pluto radios for UI selection.

    radios = iDefaultRadio();
    discovered = struct('Label', {}, 'RadioID', {});

    methods = {@iFindViaFindPlutoRadio, @iFindViaSdrDev};
    for idx = 1:numel(methods)
        try
            candidate = methods{idx}();
        catch
            candidate = struct('Label', {}, 'RadioID', {});
        end

        if ~isempty(candidate)
            discovered = iMergeRadios(discovered, candidate);
        end
    end

    if ~isempty(discovered)
        radios = iMergeRadios(iDefaultRadio(), discovered);
    end
end

function radios = iDefaultRadio()
    radios = struct('Label', {'Pluto (default)'}, 'RadioID', {'default'});
end

function radios = iFindViaFindPlutoRadio()
    radios = struct('Label', {}, 'RadioID', {});

    hasFunction = exist('findPlutoRadio', 'file') > 0 || exist('findPlutoRadio', 'builtin') > 0;
    if ~hasFunction
        return
    end

    found = findPlutoRadio();
    radios = iParseDiscoveredRows(found, 'findPlutoRadio');
end

function radios = iFindViaSdrDev()
    radios = struct('Label', {}, 'RadioID', {});

    hasFunction = exist('sdrdev', 'file') > 0 || exist('sdrdev', 'builtin') > 0;
    if ~hasFunction
        return
    end

    dev = sdrdev('Pluto');
    rows = struct([]);

    if ismethod(dev, 'info')
        try
            infoOut = info(dev);
            rows = iCoerceRows(infoOut);
        catch
        end
    end

    if isempty(rows)
        rows = iCoerceRows(dev);
    end

    radios = iParseDiscoveredRows(rows, 'sdrdev');
end

function radios = iParseDiscoveredRows(found, sourceTag)
    radios = struct('Label', {}, 'RadioID', {});
    rows = iCoerceRows(found);

    for idx = 1:numel(rows)
        row = rows(idx);
        id = iFirstField(row, {'RadioID', 'radioID', 'DeviceAddress', 'deviceAddress', 'URI', 'uri', 'Address', 'address', 'ID', 'id'});
        serial = iFirstField(row, {'SerialNum', 'serialNum', 'SerialNumber', 'serialNumber'});
        name = iFirstField(row, {'Status', 'status', 'Description', 'description', 'Name', 'name', 'Model', 'model'});

        if strlength(id) == 0 && strlength(serial) > 0
            id = serial;
        end
        if strlength(id) == 0
            id = "default";
        end

        detailParts = strings(0, 1);
        if strlength(name) > 0
            detailParts(end + 1) = name; %#ok<AGROW>
        end
        if strlength(serial) > 0
            detailParts(end + 1) = "SN " + serial; %#ok<AGROW>
        end
        if strlength(id) > 0 && id ~= "default"
            detailParts(end + 1) = id; %#ok<AGROW>
        end

        if isempty(detailParts)
            label = sprintf('Pluto %d (%s)', idx, sourceTag);
        else
            label = sprintf('Pluto %d - %s', idx, strjoin(cellstr(detailParts), ' | '));
        end

        radios(end + 1).Label = label; %#ok<AGROW>
        radios(end).RadioID = char(id);
    end
end

function rows = iCoerceRows(found)
    if istable(found)
        rows = table2struct(found);
    elseif isstruct(found)
        rows = found;
    elseif iscell(found)
        try
            rows = [found{:}];
        catch
            rows = struct([]);
        end
    elseif isobject(found)
        try
            rows = struct(found);
        catch
            rows = struct([]);
        end
    else
        rows = struct([]);
    end
end

function merged = iMergeRadios(base, extra)
    merged = base;
    seenIds = strings(0, 1);

    for idx = 1:numel(base)
        seenIds(end + 1) = string(base(idx).RadioID); %#ok<AGROW>
    end

    for idx = 1:numel(extra)
        radioId = string(extra(idx).RadioID);
        if any(seenIds == radioId)
            continue
        end
        merged(end + 1) = extra(idx); %#ok<AGROW>
        seenIds(end + 1) = radioId; %#ok<AGROW>
    end
end

function value = iFirstField(s, names)
    value = "";
    for idx = 1:numel(names)
        fieldName = names{idx};
        if isfield(s, fieldName)
            raw = s.(fieldName);
            if isstring(raw) || ischar(raw)
                if strlength(string(raw)) > 0
                    value = string(raw);
                    return
                end
            elseif isnumeric(raw) || islogical(raw)
                value = string(raw);
                return
            end
        end
    end
end
