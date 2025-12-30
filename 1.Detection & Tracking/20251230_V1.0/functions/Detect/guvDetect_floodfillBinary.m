function region = guvDetect_floodfillBinary(mask, seedRow, seedCol)
%GUVDETECT_FLOODFILLBINARY 在二值mask上做洪泛填充（imreconstruct）。
seed = false(size(mask));
seed(seedRow, seedCol) = true;
region = imreconstruct(seed, mask);
end
