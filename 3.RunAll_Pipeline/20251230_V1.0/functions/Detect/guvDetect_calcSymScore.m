function SymScore = guvDetect_calcSymScore(subMask, orientationDeg)
%GUVDETECT_CALCSYMSCORE 形态对称性分数：主轴对齐后左右镜像 IoU。
if isempty(subMask) || ~any(subMask(:))
    SymScore = NaN; return;
end

ImgRot = imrotate(double(subMask), 90 - orientationDeg, 'bilinear', 'crop');
MaskRot = ImgRot > 0.5;
if ~any(MaskRot(:))
    SymScore = NaN; return;
end

col_sum = sum(MaskRot, 1);
if sum(col_sum) == 0
    SymScore = NaN; return;
end
center_x = sum(col_sum .* (1:numel(col_sum))) / sum(col_sum);

W = size(MaskRot, 2);
splitCol = round(center_x);
if splitCol < 1 || splitCol >= W
    SymScore = NaN; return;
end

LeftPart  = MaskRot(:, 1:splitCol);
RightPart = MaskRot(:, splitCol+1:end);

targetW = max(size(LeftPart,2), size(RightPart,2));
Lpad = padarray(LeftPart,  [0, targetW - size(LeftPart,2)], 0, 'pre');
Rpad = padarray(RightPart, [0, targetW - size(RightPart,2)], 0, 'post');

Lflip = fliplr(Lpad);
U = (Lflip | Rpad);
if ~any(U(:))
    SymScore = NaN; return;
end
I = (Lflip & Rpad);

SymScore = sum(I(:)) / sum(U(:));
end
