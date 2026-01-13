function idx = guvDetect_boundaryPath(iStart, iEnd, N, dirSign)
%GUVDETECT_BOUNDARYPATH 沿闭合轮廓的索引路径（dirSign=+1正向，-1反向）。
if dirSign > 0
    if iStart <= iEnd
        idx = (iStart:iEnd)';
    else
        idx = [iStart:N, 1:iEnd]';
    end
else
    if iStart >= iEnd
        idx = (iStart:-1:iEnd)';
    else
        idx = [iStart:-1:1, N:-1:iEnd]';
    end
end
end
