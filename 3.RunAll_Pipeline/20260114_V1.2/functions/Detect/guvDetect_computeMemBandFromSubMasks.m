function [memBandMasksList, memIntensityList] = guvDetect_computeMemBandFromSubMasks(I_raw, bboxesList, subMasksList, opts)
%GUVDETECT_COMPUTEMEMBANDFROMSUBMASKS 基于 subMask 生成膜 band 薄环并计算薄环平均强度。
% 与 detectGUVRegions 中实现一致：
%   1) subMask -> fill holes -> open/close 平滑
%   2) outer = imdilate(...thickR), inner = imerode(...)
%   3) band = outer & ~inner
%   4) 在 bbox crop 区域上用 band 采样 I_norm 求 mean

if nargin < 4, opts = struct(); end
if isfield(opts,'mem') && isfield(opts.mem,'smoothR'), smoothR = opts.mem.smoothR; else, smoothR = 2; end
if isfield(opts,'mem') && isfield(opts.mem,'thickR'),  thickR  = opts.mem.thickR;  else, thickR  = 3; end

[H,W] = size(I_raw);
memBandMasksList = cell(size(subMasksList));
memIntensityList = nan(numel(subMasksList),1);

seS = strel('disk', smoothR);
seT = strel('disk', thickR);
seE = strel('disk', max(thickR-1,1));

for kk = 1:numel(subMasksList)
    m0 = subMasksList{kk};
    if isempty(m0)
        memBandMasksList{kk} = [];
        memIntensityList(kk) = nan;
        continue;
    end
    m1 = imfill(logical(m0), 'holes');
    m1 = imopen(imclose(m1, seS), seS);
    outer = imdilate(m1, seT);
    inner = imerode(m1, seE);
    band = outer & ~inner;
    memBandMasksList{kk} = band;

    if kk <= size(bboxesList,1)
        bb = bboxesList(kk,:);
        x1 = max(1, floor(bb(1))+1);
        y1 = max(1, floor(bb(2))+1);
        x2 = min(W, floor(bb(1)+bb(3)));
        y2 = min(H, floor(bb(2)+bb(4)));
        if x2>=x1 && y2>=y1
            crop = I_raw(y1:y2, x1:x2);
            bh = size(band,1); bw2 = size(band,2);
            ch = size(crop,1); cw = size(crop,2);
            hh = min(bh,ch); ww = min(bw2,cw);
            if hh>0 && ww>0
                band2 = band(1:hh,1:ww);
                crop2 = crop(1:hh,1:ww);
                v = crop2(band2);
                if ~isempty(v)
                    memIntensityList(kk) = mean(v);
                else
                    memIntensityList(kk) = nan;
                end
            end
        end
    end
end
end
