function guvIO_frameStoreCreateH5(h5Path, H, W, T, deflateLevel)
%GUVFRAMESTORE_CREATEH5 创建用于存储整段时间序列的 HDF5 图像仓库
% 目的：避免把整幅图像重复保存到每帧 MAT 或 TTracks 中，降低内存/磁盘压力。
%
% 输入：
%   h5Path       - 输出 H5 路径（若已存在建议先删除）
%   H,W,T        - 图像尺寸与帧数
%   deflateLevel - 压缩等级（0~9；3 通常速度/体积折中较好）

if nargin < 5 || isempty(deflateLevel)
    deflateLevel = 3;
end

if exist(h5Path,'file')
    delete(h5Path);
end

% 每帧一个 chunk，便于随机按帧读取
h5create(h5Path, '/I', [H W T], ...
    'Datatype', 'uint16', ...
    'ChunkSize', [H W 1], ...
    'Deflate', deflateLevel);
end
