function guvIO_frameStoreWriteFrameH5(h5Path, I, t, datasetName)
%GUVFRAMESTORE_WRITEFRAMEH5 把第 t 帧写入 HDF5 图像仓库
% 输入：
%   h5Path - H5 文件路径
%   I      - 2D uint16 图像
%   t      - 帧号（从 1 开始）
%   datasetName - 数据集名（默认 '/I'）

if nargin < 4 || isempty(datasetName)
    datasetName = '/I';
end

[h, w] = size(I);
h5write(h5Path, datasetName, uint16(I), [1 1 t], [h w 1]);
end
