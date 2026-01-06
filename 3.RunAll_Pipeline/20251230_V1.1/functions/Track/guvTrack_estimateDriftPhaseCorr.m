function drift = guvTrack_estimateDriftPhaseCorr(I1, I2)
    A = double(I1); B = double(I2);
    A = A - mean(A(:)); B = B - mean(B(:));

    [H,W] = size(A);
    wx = 0.5 - 0.5*cos(2*pi*(0:W-1)/(W-1));
    wy = 0.5 - 0.5*cos(2*pi*(0:H-1)/(H-1));
    win = wy(:)*wx(:).';
    A = A.*win; B = B.*win;

    FA = fft2(A); FB = fft2(B);
    R = FA .* conj(FB);
    R = R ./ (abs(R) + eps);

    r = real(fftshift(ifft2(R)));
    [~, idx] = max(r(:));
    [py, px] = ind2sub(size(r), idx);

    cy = floor(H/2)+1;
    cx = floor(W/2)+1;

    dy = py - cy;
    dx = px - cx;

    drift = [dx, dy];
end
