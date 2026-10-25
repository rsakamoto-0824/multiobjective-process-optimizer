function [names,labels]=gprKernels()
%GPRKERNELS Built-in covariance functions available in the supported releases.
names={'ardsquaredexponential','ardexponential','ardmatern32','ardmatern52', ...
    'ardrationalquadratic','squaredexponential','exponential','matern32','matern52','rationalquadratic'};
labels={'二乗指数 (ARD)','指数 (ARD)','Matern 3/2 (ARD)','Matern 5/2 (ARD)', ...
    '有理二次 (ARD)','二乗指数','指数','Matern 3/2','Matern 5/2','有理二次'};
end
