setviews;

fprintf('qmin = %24.16e\n',qmin);
fprintf('qmax = %24.16e\n',qmax);

colormap(parula);
showpatchborders;
setpatchborderprops('linewidth',1);
daspect([1,1,1]);
colorbar;

caxis([0,1])
axis off;

% view(vfront);
view(3)

prt = false;
NoQuery = false;
if (prt)
    delete(get(gca,'title'));
    fname = sprintf('torus%02d.png',Frame);
    print('-dpng','-r640',fname);
end
shg
