function f1 = guvDetect_makeDebugFigure(I_norm, innerMask, innerData, memMask, memData, GUVData)
%GUVDETECT_MAKEDEBUGFIGURE 生成 detect 四宫格调试图。
f1 = figure('Name','detectGUVRegions debug','Color','w');

subplot(2,2,1); imshow(I_norm,[]); hold on;
if ~isempty(innerData.centroids)
    plot(innerData.centroids(:,1), innerData.centroids(:,2), 'r+', 'MarkerSize', 8, 'LineWidth', 1.5);
end
if ~isempty(memData.centroids)
    plot(memData.centroids(:,1), memData.centroids(:,2), 'c+', 'MarkerSize', 8, 'LineWidth', 1.5);
end
title('I_{norm} + inner(red) + mem(cyan)'); hold off;

subplot(2,2,2); imshow(innerMask,[]); hold on;
if ~isempty(innerData.centroids)
    plot(innerData.centroids(:,1), innerData.centroids(:,2), 'r+', 'MarkerSize', 8, 'LineWidth', 1.5);
end
title('innerMask / innerData'); hold off;

subplot(2,2,3); imshow(memMask,[]); hold on;
if ~isempty(memData.centroids)
    plot(memData.centroids(:,1), memData.centroids(:,2), 'c+', 'MarkerSize', 8, 'LineWidth', 1.5);
end
title('memMask / memData'); hold off;

subplot(2,2,4); imshow(I_norm,[]); hold on;
if ~isempty(GUVData.centroids)
    plot(GUVData.centroids(:,1), GUVData.centroids(:,2), 'g+', 'MarkerSize', 9, 'LineWidth', 1.5);
end
title('GUVData centroids'); hold off;

end
