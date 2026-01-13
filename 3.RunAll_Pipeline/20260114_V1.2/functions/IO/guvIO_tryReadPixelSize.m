function px = guvIO_tryReadPixelSize(reader, fallback)
%GUVTRYREADPIXELSIZE try to read physical pixel size from Bio-Formats metadata
px = fallback;
try
    store = reader.getMetadataStore();
    v = store.getPixelsPhysicalSizeX(0);
    if ~isempty(v)
        tmp = double(v.value());
        if ~isempty(tmp) && isfinite(tmp) && tmp > 0
            px = tmp;
        end
    end
catch
    % keep fallback
end
end
