function cfg = guvPipeline_LoadConfig(configPath)
% LoadConfig 读取 JSON 配置文件，返回 MATLAB 结构体 cfg
%
%   cfg = LoadConfig(configPath)
%     configPath: JSON 配置文件的完整路径

    if ~isfile(configPath)
        error('配置文件不存在：%s', configPath);
    end

    txt = fileread(configPath);
    try
        cfg = jsondecode(txt);
    catch ME
        error('解析 JSON 配置失败：%s\n%s', configPath, ME.message);
    end

    % （可选）后续可以在这里做 cfg 校验，确保必须字段存在
end
