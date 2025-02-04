c
!> For each coarse-fine interface, a Riemann problem between an inner
!! ghost cell value on the fine grid and cell value in the adjacent coarse
!! cell must be solved and added to corresponding location in
!! **node(ffluxptr, mptr)** for conservative fix later
!!
c -------------------------------------------------------------
c
       subroutine qad_modified(valbig,mitot,mjtot,nvar,
     .                svdflx,qc1d,lenbc,lratiox,lratioy,hx,hy,
     .                maux,aux,auxc1d,delt,mptr)

      use amr_module
       implicit double precision (a-h, o-z)


       logical qprint

       dimension valbig(nvar,mitot,mjtot)
       dimension qc1d(nvar,lenbc)
       dimension svdflx(nvar,lenbc)
       dimension aux(maux,mitot,mjtot)
       dimension auxc1d(maux,lenbc)

c
c ::::::::::::::::::::::::::: QAD ::::::::::::::::::::::::::::::::::
c  are added in to coarse grid value, as a conservation fixup. 
c  Done each fine grid time step. If source terms are present, the
c  coarse grid value is advanced by source terms each fine time step too.

c  No change needed in this sub. for spherical mapping: correctly
c  mapped vals already in bcs on this fine grid and coarse saved
c  vals also properly prepared
c
c Side 1 is the left side of the fine grid patch.  Then go around clockwise.
c ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
c
c      # local storage
c      # note that dimension here are bigger than dimensions used
c      # in rp2, but shouldn't matter since wave is not used in qad
c      # and for other arrays it is only the last parameter that is wrong
c      #  ok as long as meqn, mwaves < maxvar

       parameter (max1dp1 = max1d+1)
       dimension ql(nvar,max1dp1),    qr(nvar,max1dp1)
       dimension wave(nvar,mwaves,max1dp1), s(mwaves,max1dp1)
       dimension amdq(nvar,max1dp1),  apdq(nvar,max1dp1)
       dimension auxl(maxaux*max1dp1),  auxr(maxaux*max1dp1)

       integer idir, iface
       logical use_fix
c
c  WARNING: auxl,auxr dimensioned at max possible, but used as if
c  they were dimensioned as the real maux by max1dp1. Would be better
c  of course to dimension by maux by max1dp1 but this wont work if maux=0
c  So need to access using your own indexing into auxl,auxr.
       iaddaux(iaux,i) = iaux + maux*(i-1)

       data qprint/.false./
       data use_fix /.true./

c
c      aux is auxiliary array with user parameters needed in Riemann solvers
c          on fine grid corresponding to valbig
c      auxc1d is coarse grid stuff from around boundary, same format as qc1d
c      auxl, auxr are work arrays needed to pass stuff to rpn2
c      maux is the number of aux variables, which may be zero.
c

       tgrid = rnode(timemult, mptr)
       if (qprint) 
     .      write(dbugunit,*)" working on grid ",mptr," time ",tgrid
       nc = mjtot-2*nghost
       nr = mitot-2*nghost
       level = node(nestlevel, mptr)
       index = 0

c
c--------
c  side 1
c--------
c
       do 10 j = nghost+1, mjtot-nghost
       if (maux.gt.0) then
          do 5 ma = 1,maux
             if (auxtype(ma).eq."xleft") then
c                # Assuming velocity at left-face, this fix
c                # preserves conservation in incompressible flow:
                 auxl(iaddaux(ma,j-nghost+1)) = aux(ma,nghost+1,j)
               else
c                # Normal case -- we set the aux arrays 
c                # from the cell corresponding  to q
                 auxl(iaddaux(ma,j-nghost+1)) = aux(ma,nghost,j)
               endif
  5          continue
          endif
       do 10 ivar = 1, nvar
         ql(ivar,j-nghost+1) = valbig(ivar,nghost,j)
 10    continue

       lind = 0
       ncrse = (mjtot-2*nghost)/lratioy
       do 20 jc = 1, ncrse
         index = index + 1
         do 25 l = 1, lratioy
         lind = lind + 1
         if (maux.gt.0) then
            do 24 ma=1,maux
               auxr(iaddaux(ma,lind)) = auxc1d(ma,index)
   24          continue
            endif
         do 25 ivar = 1, nvar
 25         qr(ivar,lind) = qc1d(ivar,index)
 20    continue
    
       if (qprint) then
         write(dbugunit,*) 'side 1, ql and qr:'
         do i=2,nc
            write(dbugunit,4101) i,qr(1,i-1),ql(1,i)
          enddo
 4101      format(i3,4e16.6)
         if (maux .gt. 0) then
             write(dbugunit,*) 'side 1, auxr:'
             do i=2,nc
                write(dbugunit,4101) i,(auxr(iaddaux(ma,i-1)),ma=1,maux)
                enddo
             write(dbugunit,*) 'side 1, auxl:'
             do i=2,nc
                write(dbugunit,4101) i,(auxl(iaddaux(ma,i)),ma=1,maux)
                enddo
         endif
       endif
 
c      # Side 1
       if (use_fix) then
c          # Compute f(ql) - f(qr) explicitly        
           idir = 0
           iface = 0    !! Face of Cartesian grid
           call rpn2qad(nc,nvar,maux,nghost, idir, iface, 
     &                  ql,qr,auxl,auxr,amdq,apdq)
       else
c          # Re-purpose user Riemann solver       
           call rpn2(1,max1dp1-2*nghost,nvar,mwaves,maux,nghost,
     &               nc+1-2*nghost,ql,qr,auxl,auxr,wave,s,amdq,apdq)
       endif           



c
c we have the wave. for side 1 add into sdflxm
c
       influx = 0
       do 30 j = 1, nc/lratioy
          influx  = influx + 1
          jfine = (j-1)*lratioy
          do 40 ivar = 1, nvar
            do 50 l = 1, lratioy
              svdflx(ivar,influx) = svdflx(ivar,influx) 
     .                     + amdq(ivar,jfine+l+1) * hy * delt
     .                     + apdq(ivar,jfine+l+1) * hy * delt
 50         continue
 40       continue
 30    continue

c--------
c  side 2
c--------
c
       if (mjtot .eq. 2*nghost+1) then
c          # a single row of interior cells only happens when using the
c          # 2d amrclaw code to do a 1d problem with refinement.
c          # (feature added in Version 4.3)
c          # skip over sides 2 and 4 in this case
           go to 299
           endif

       do 210 i = nghost+1, mitot-nghost
        if (maux.gt.0) then
          do 205 ma = 1,maux
             auxr(iaddaux(ma,i-nghost)) = aux(ma,i,mjtot-nghost+1)
 205         continue
          endif
        do 210 ivar = 1, nvar
            qr(ivar,i-nghost) = valbig(ivar,i,mjtot-nghost+1)
 210    continue

       lind = 0
       ncrse = (mitot-2*nghost)/lratiox
       do 220 ic = 1, ncrse
         index = index + 1
         do 225 l = 1, lratiox
         lind = lind + 1
         if (maux.gt.0) then
            do 224 ma=1,maux
             if (auxtype(ma).eq."yleft") then
c                # Assuming velocity at bottom-face, this fix
c                # preserves conservation in incompressible flow:
c                # This assumes that the coarse grid aux variable is the 
c                # same as the fine grid variable, i.e. edges match.
                 ifine = (ic-1)*lratiox + nghost + l
                 auxl(iaddaux(ma,lind+1)) = aux(ma,ifine,mjtot-nghost+1)
               else
                 auxl(iaddaux(ma,lind+1)) = auxc1d(ma,index)
               endif
  224          continue
            endif
         do 225 ivar = 1, nvar
 225         ql(ivar,lind+1) = qc1d(ivar,index)
 220    continue
    
       if (qprint) then
         write(dbugunit,*) 'side 2, ql and qr:'
         do i=1,nr
            write(dbugunit,4101) i,ql(1,i+1),qr(1,i)
            enddo
         if (maux .gt. 0) then
             write(dbugunit,*) 'side 2, auxr:'
             do i = 1, nr
                write(dbugunit,4101) i, (auxr(iaddaux(ma,i)),ma=1,maux)
                enddo
             write(dbugunit,*) 'side 2, auxl:'
             do i = 1, nr
                write(dbugunit,4101) i, (auxl(iaddaux(ma,i)),ma=1,maux)
                enddo
         endif
       endif

c      # Side 2 
       if (use_fix) then
c          # Compute f(ql) - f(qr) explicitly        
           idir = 1
           iface = 3
           CALL rpn2qad(nr,nvar,maux,nghost, idir, iface, 
     &                  ql,qr,auxl,auxr,amdq,apdq)
       else
c          # Re-purpose user Riemann solver       
           call rpn2(2,max1dp1-2*nghost,nvar,mwaves,maux,nghost,
     &               nr+1-2*nghost,ql,qr,auxl,auxr,wave,s,amdq,apdq)
       endif



c
c we have the wave. for side 2. add into sdflxp
c
       do 230 i = 1, nr/lratiox
          influx  = influx + 1
          ifine = (i-1)*lratiox
          do 240 ivar = 1, nvar
            do 250 l = 1, lratiox
              svdflx(ivar,influx) = svdflx(ivar,influx) 
     .                     - amdq(ivar,ifine+l+1) * hx * delt
     .                     - apdq(ivar,ifine+l+1) * hx * delt
 250         continue
 240       continue
 230    continue

 299  continue

c--------
c  side 3
c--------
c
       do 310 j = nghost+1, mjtot-nghost
        if (maux.gt.0) then
          do 305 ma = 1,maux
             auxr(iaddaux(ma,j-nghost)) = aux(ma,mitot-nghost+1,j)
 305         continue
          endif
        do 310 ivar = 1, nvar
          qr(ivar,j-nghost) = valbig(ivar,mitot-nghost+1,j)
 310      continue

       lind = 0
       ncrse = (mjtot-2*nghost)/lratioy
       do 320 jc = 1, ncrse
         index = index + 1
         do 325 l = 1, lratioy
         lind = lind + 1
         if (maux.gt.0) then
            do 324 ma=1,maux
             if (auxtype(ma).eq."xleft") then
c                # Assuming velocity at left-face, this fix
c                # preserves conservation in incompressible flow:
                 jfine = (jc-1)*lratioy + nghost + l
                 auxl(iaddaux(ma,lind+1)) = aux(ma,mitot-nghost+1,jfine)
               else
                 auxl(iaddaux(ma,lind+1)) = auxc1d(ma,index)
               endif
  324          continue
            endif
         do 325 ivar = 1, nvar
 325         ql(ivar,lind+1) = qc1d(ivar,index)
 320    continue
    
       if (qprint) then
         write(dbugunit,*) 'side 3, ql and qr:'
         do i=1,nc
            write(dbugunit,4101) i,ql(1,i),qr(1,i)
            enddo
       endif

c      # Side 3
       if (use_fix) then
c          # Compute f(ql) - f(qr) explicitly        
           idir = 0
           iface = 1
           CALL rpn2qad(nc,nvar,maux,nghost, idir, iface, 
     &                  ql,qr,auxl,auxr,amdq,apdq)
       else
c          # Re-purpose user Riemann solver       
           call rpn2(1,max1dp1-2*nghost,nvar,mwaves,maux,nghost,
     &               nc+1-2*nghost,ql,qr,auxl,auxr,wave,s,amdq,apdq)
       endif


c
c we have the wave. for side 3 add into sdflxp
C
       sgn = -1  !! Sign
       do 330 j = 1, nc/lratioy
          influx  = influx + 1
          jfine = (j-1)*lratioy
          do 340 ivar = 1, nvar
            do 350 l = 1, lratioy
              svdflx(ivar,influx) = svdflx(ivar,influx) 
     .                     - amdq(ivar,jfine+l+1) * hy * delt
     .                     - apdq(ivar,jfine+l+1) * hy * delt
 350         continue
 340       continue
 330    continue

c--------
c  side 4
c--------
c
       if (mjtot .eq. 2*nghost+1) then
c          # a single row of interior cells only happens when using the
c          # 2d amrclaw code to do a 1d problem with refinement.
c          # (feature added in Version 4.3)
c          # skip over sides 2 and 4 in this case
           go to 499
           endif
c
       do 410 i = nghost+1, mitot-nghost
        if (maux.gt.0) then
          do 405 ma = 1,maux
             if (auxtype(ma).eq."yleft") then
c                # Assuming velocity at bottom-face, this fix
c                # preserves conservation in incompressible flow:
                 auxl(iaddaux(ma,i-nghost+1)) = aux(ma,i,nghost+1)
               else
                 auxl(iaddaux(ma,i-nghost+1)) = aux(ma,i,nghost)
               endif
 405         continue
          endif
        do 410 ivar = 1, nvar
          ql(ivar,i-nghost+1) = valbig(ivar,i,nghost)
 410      continue

       lind = 0
       ncrse = (mitot-2*nghost)/lratiox
       do 420 ic = 1, ncrse
         index = index + 1
         do 425 l = 1, lratiox
         lind = lind + 1
         if (maux.gt.0) then
            do 424 ma=1,maux
               auxr(iaddaux(ma,lind)) = auxc1d(ma,index)
  424          continue
            endif
         do 425 ivar = 1, nvar
 425         qr(ivar,lind) = qc1d(ivar,index)
 420    continue
    
       if (qprint) then
         write(dbugunit,*) 'side 4, ql and qr:'
         do i=1,nr
            write(dbugunit,4101) i, ql(1,i),qr(1,i)
            enddo
       endif

c      # Side 4
       if (use_fix) then
c          # Compute f(ql) - f(qr) explicitly        
           idir = 1
           iface = 2
           CALL rpn2qad(nr,nvar,maux,nghost, idir, iface,                 
     &                  ql,qr,auxl,auxr,amdq,apdq)
       else
c          # Re-purpose user Riemann solver       
           call rpn2(2,max1dp1-2*nghost,nvar,mwaves,maux,nghost,
     &               nr+1-2*nghost,ql,qr,auxl,auxr,wave,s,amdq,apdq)
       endif

c
c we have the wave. for side 4. add into sdflxm
c
       do 430 i = 1, nr/lratiox
          influx  = influx + 1
          ifine = (i-1)*lratiox
          do 440 ivar = 1, nvar
            do 450 l = 1, lratiox
              svdflx(ivar,influx) = svdflx(ivar,influx) 
     .                     + amdq(ivar,ifine+l+1) * hx * delt
     .                     + apdq(ivar,ifine+l+1) * hx * delt
 450         continue
 440       continue
 430    continue

 499   continue

c      # for source terms:
       if (method(5) .ne. 0) then   ! should I test here if index=0 and all skipped?
           call src1d(nvar,nghost,lenbc,qc1d,maux,auxc1d,tgrid,delt)
c      # how can this be right - where is the integrated src term used?
           endif
           
       return
       end


      subroutine rpn2qad(mx,meqn,maux,mbc, idir, iface, 
     &        ql,qr,auxl,auxr,amdq,apdq)

      implicit none
      integer mx, meqn, maux, mbc, idir, iface
      double precision ql(meqn,0:mx-1),   qr(meqn,mx)
      double precision auxl(maux,0:mx-1), auxr(maux,mx)

      double precision amdq(meqn,0:mx)  
      double precision apdq(meqn,0:mx)

c     # automatically allocated
      double PRECISION qvl(meqn),   qvr(meqn)
      double PRECISION auxvl(maux), auxvr(maux)
      double PRECISION fluxl(meqn), fluxr(meqn)

      double precision fd
      integer m,i, iface_cell

c     # idir refers to direction of the Riemann solver
c     # iface refers to the face of the Cartesian grid (not face of cell)

      do i = 1,mx
        do m = 1,maux
             auxvl(m) = auxl(m,i)
             auxvr(m) = auxr(m,i)
        end do

        do m = 1,meqn
            qvl(m) = ql(m,i)
            qvr(m) = qr(m,i)
        end do


c       # Get face relative to ghost cell
c       # Left face of Cartesian grid   --> right edge of ghost cell
c       # Right face of Cartesian grid  --> left edge of ghost cell
c       # Bottom face of Cartesian grid --> top edge of ghost cell
c       # Top face of Cartesian grid    --> bottom edge of ghost cell
        if (idir .eq. 0) then
            iface_cell = 1-iface    !! Swap left and right edges
        else
            iface_cell = 5-iface    !! Swap bottom and top edges
        endif

c       # Call user defined function to compute fluxes.  The resulting
c       # flux should be those projected onto face 'iface_cell' and 
c       # scaled by edgelength/dx or edgelength/dy.
c       #
c       # For equations in non-conservative form, the fluxes can be
c       # set to 0
        call rpn2qad_flux(meqn,maux,idir,iface_cell,qvl,auxvl,fluxl)
        call rpn2qad_flux(meqn,maux,idir,iface_cell,qvr,auxvr,fluxr)

        do m = 1,meqn
c           # Note that we don't scale fluxc by 0.5 (as in paper). 
c           # This scaling is taken into account by scaling done
c           # in fluxes.          
            fd = fluxl(m) - fluxr(m)
            apdq(m,i) = 0.5*fd  
            amdq(m,i) = 0.5*fd
        enddo

      enddo

      end
