function Geom = guvDetect_subsetGeom(Geom, validMask)
%GUVDETECT_SUBSETGEOM 按 validMask 选择几何字段的行。
fn = fieldnames(Geom);
for i=1:numel(fn)
    Geom.(fn{i}) = Geom.(fn{i})(validMask,:);
end
end
