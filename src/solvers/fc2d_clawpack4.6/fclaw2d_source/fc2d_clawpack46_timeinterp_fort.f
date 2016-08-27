      subroutine fc2d_clawpack46_fort_timeinterp
     &      (mx,my,mbc,meqn,psize,
     &      qcurr,qlast,qinterp,alpha,ierror)
      implicit none

      integer mx,my,mbc,meqn,psize, ierror
      double precision alpha
      double precision   qcurr(1-mbc:mx+mbc,1-mbc:my+mbc,meqn)
      double precision   qlast(1-mbc:mx+mbc,1-mbc:my+mbc,meqn)
      double precision qinterp(1-mbc:mx+mbc,1-mbc:my+mbc,meqn)

      integer i,j, m,mint,k,kfinal, ng

c     # Number of interior layers to compute.  Since we only
c     # interpolate from time-interpolated levels, we only
c     # need two layers.  If we were averaging, we'd need four.
      mint = 2
      ierror = 0
      k = 1

c     # This could also be set to 0 or 1.  But be sure to also set
c     # set ng in fclaw2d_clawpatch_setup_timeinterp.
      ng = 0

      do m = 1,meqn
c        # Face 0
         do j = 1-ng,my-mint
            do i = 1-ng,mint
               qinterp(i,j,m) = qlast(i,j,m) +
     &               alpha*(qcurr(i,j,m)-qlast(i,j,m))
               k = k + 1
            enddo
         enddo

c        # Face 2
         do j = 1-ng,mint
            do i = mint+1,mx+ng
               qinterp(i,j,m) = qlast(i,j,m) +
     &               alpha*(qcurr(i,j,m)-qlast(i,j,m))
               k = k + 1
            enddo
         enddo

c        # Face 1
         do j = mint+1,my+ng
            do i = mx-mint+1,mx+ng
               qinterp(i,j,m) = qlast(i,j,m) +
     &               alpha*(qcurr(i,j,m)-qlast(i,j,m))
               k = k + 1
            enddo
         enddo

c        # Face 3
         do j = my-mint+1,my+ng
            do i = 1-ng,mx-mint
               qinterp(i,j,m) = qlast(i,j,m) +
     &               alpha*(qcurr(i,j,m)-qlast(i,j,m))
               k = k + 1
            enddo
         enddo

      enddo

      kfinal = k-1;
      if (kfinal .ne. psize) then
         ierror = 2
      endif


      end
