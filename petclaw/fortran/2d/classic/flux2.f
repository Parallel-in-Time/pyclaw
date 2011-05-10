c
c
c
c     =====================================================
      subroutine flux2(ixy,maxm,meqn,mwaves,maux,mbc,mx,
     &                 q1d,dtdx1d,aux1,aux2,aux3,method,mthlim,
     &               qadd,fadd,gadd,cfl1d,wave,s,
     &                 amdq,apdq,cqxx,bmasdq,bpasdq,rpn2,rpt2)
c     =====================================================
c
c     # Compute the modification to fluxes f and g that are generated by
c     # all interfaces along a 1D slice of the 2D grid. 
c     #    ixy = 1  if it is a slice in x
c     #          2  if it is a slice in y
c     # This value is passed into the Riemann solvers. The flux modifications
c     # go into the arrays fadd and gadd.  The notation is written assuming
c     # we are solving along a 1D slice in the x-direction.
c
c     # fadd(i,.) modifies F to the left of cell i
c     # gadd(i,.,1) modifies G below cell i
c     # gadd(i,.,2) modifies G above cell i
c
c     # The method used is specified by method(2:3):
c
c         method(2) = 1 if only first order increment waves are to be used.
c                   = 2 if second order correction terms are to be added, with
c                       a flux limiter as specified by mthlim.  
c
c         method(3) = 0 if no transverse propagation is to be applied.
c                       Increment and perhaps correction waves are propagated
c                       normal to the interface.
c                   = 1 if transverse propagation of increment waves 
c                       (but not correction waves, if any) is to be applied.
c                   = 2 if transverse propagation of correction waves is also
c                       to be included.  
c
c     Note that if method(6)=1 then the capa array comes into the second 
c     order correction terms, and is already included in dtdx1d:
c     If ixy = 1 then
c        dtdx1d(i) = dt/dx                 if method(6) = 0
c                  = dt/(dx*capa(i,jcom))  if method(6) = 1
c     If ixy = 2 then
c        dtdx1d(j) = dt/dy                 if method(6) = 0
c                  = dt/(dy*capa(icom,j))  if method(6) = 1
c
c     Notation:
c        The jump in q (q1d(i,:)-q1d(i-1,:))  is split by rpn2 into
c            amdq =  the left-going flux difference  A^- Delta q  
c            apdq = the right-going flux difference  A^+ Delta q  
c        Each of these is split by rpt2 into 
c            bmasdq = the down-going transverse flux difference B^- A^* Delta q
c            bpasdq =   the up-going transverse flux difference B^+ A^* Delta q
c        where A^* represents either A^- or A^+.
c
c
      implicit double precision (a-h,o-z)
      external rpn2,rpt2
      dimension    q1d(meqn, 1-mbc:maxm+mbc)
      dimension   amdq(meqn, 1-mbc:maxm+mbc)
      dimension   apdq(meqn, 1-mbc:maxm+mbc)
      dimension bmasdq(meqn, 1-mbc:maxm+mbc)
      dimension bpasdq(meqn, 1-mbc:maxm+mbc)
      dimension   cqxx(meqn, 1-mbc:maxm+mbc)
      dimension   qadd(meqn, 1-mbc:maxm+mbc)
      dimension   fadd(meqn, 1-mbc:maxm+mbc)
      dimension   gadd(meqn, 2, 1-mbc:maxm+mbc)
c
      dimension dtdx1d(1-mbc:maxm+mbc)
      dimension aux1(maux,1-mbc:maxm+mbc)
      dimension aux2(maux,1-mbc:maxm+mbc)
      dimension aux3(maux,1-mbc:maxm+mbc)
c
      dimension     s(mwaves,1-mbc:maxm+mbc)
      dimension  wave(meqn, mwaves, 1-mbc:maxm+mbc)
c
      dimension method(7),mthlim(mwaves)
      logical limit
      common /comxyt/ dtcom,dxcom,dycom,tcom,icom,jcom
c
      limit = .false.
      do 5 mw=1,mwaves
         if (mthlim(mw) .gt. 0) limit = .true.
   5  continue
c
c     # initialize flux increments:
c     -----------------------------
c
      forall (m=1:meqn, i = 1-mbc: mx+mbc)
	     qadd(m,i) = 0.d0
	     fadd(m,i) = 0.d0
	     gadd(m,1,i) = 0.d0
	     gadd(m,2,i) = 0.d0
      end forall
  
c
c     # solve Riemann problem at each interface and compute Godunov updates
c     ---------------------------------------------------------------------
c
      call rpn2(ixy,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux2,aux2,
     &        wave,s,amdq,apdq)
c
c     # Set qadd for the donor-cell upwind method (Godunov)
      forall(m=1:meqn, i=1:mx+1)
	     qadd(m,i) = qadd(m,i) - dtdx1d(i)*apdq(m,i)
		 qadd(m,i-1) = qadd(m,i-1) - dtdx1d(i-1)*amdq(m,i)
      end forall
c
c     # compute maximum wave speed for checking Courant number:
      cfl1d = 0.d0
      do 51 mw=1,mwaves
         do 50 i=1,mx+1
c          # if s>0 use dtdx1d(i) to compute CFL,
c          # if s<0 use dtdx1d(i-1) to compute CFL:
            cfl1d = dmax1(cfl1d, dtdx1d(i)*s(mw,i), 
     &                          -dtdx1d(i-1)*s(mw,i))
   50    continue
   51 continue
c
      if (method(2).eq.1) go to 130
c
c     # modify F fluxes for second order q_{xx} correction terms:
c     -----------------------------------------------------------
c
c     # apply limiter to waves:
      if (limit) call limiter(maxm,meqn,mwaves,mbc,mx,wave,s,mthlim)
c
      do 120 i = 2-mbc, mx+mbc
c
c     # For correction terms below, need average of dtdx in cell
c     # i-1 and i.  Compute these and overwrite dtdx1d:
c
c        # modified in Version 4.3 to use average only in cqxx, not transverse
         dtdxave = 0.5d0 * (dtdx1d(i-1) + dtdx1d(i))
c
         do 120 m=1,meqn
            cqxx(m,i) = 0.d0
            do 119 mw=1,mwaves
c
c              # second order corrections:
               cqxx(m,i) = cqxx(m,i) + dabs(s(mw,i))
     &            * (1.d0 - dabs(s(mw,i))*dtdxave) * wave(m,mw,i)
c
  119       continue
            fadd(m,i) = fadd(m,i) + 0.5d0 * cqxx(m,i)
  120    continue
  121 continue
c
c
  130  continue
c
      if (method(3).le.0) go to 999   !# no transverse propagation
c
      if (method(2).gt.1 .and. method(3).eq.2) then
c        # incorporate cqxx into amdq and apdq so that it is split also.
         forall (m=1:meqn, i = 1: mx+1)
               amdq(m,i) = amdq(m,i) + cqxx(m,i)
               apdq(m,i) = apdq(m,i) - cqxx(m,i)
         end forall
      endif
c
c
c      # modify G fluxes for transverse propagation
c      --------------------------------------------
c
c
c     # split the left-going flux difference into down-going and up-going:
      call rpt2(ixy,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,aux3,
     &        1,amdq,bmasdq,bpasdq)
c
c     # modify flux below and above by B^- A^- Delta q and  B^+ A^- Delta q:
      forall ( m=1:meqn , i = 1:mx+1)
	     gadd(m,1,i-1) = gadd(m,1,i-1) - 
     &                 0.5d0*dtdx1d(i-1) * bmasdq(m,i)
	     gadd(m,2,i-1) = gadd(m,2,i-1) -
     &                 0.5d0*dtdx1d(i-1) * bpasdq(m,i)
	  end forall
 
c
c     # split the right-going flux difference into down-going and up-going:
      call rpt2(ixy,maxm,meqn,mwaves,mbc,mx,q1d,q1d,aux1,aux2,aux3,
     &        2,apdq,bmasdq,bpasdq)
c
c     # modify flux below and above by B^- A^+ Delta q and  B^+ A^+ Delta q:
      forall ( m=1:meqn , i = 1: mx+1)
            gadd(m,1,i) = gadd(m,1,i) - 
     &                0.5d0*dtdx1d(i) * bmasdq(m,i)
            gadd(m,2,i) = gadd(m,2,i) - 
     &                0.5d0*dtdx1d(i) * bpasdq(m,i)
      end forall
c
  999 continue
      return
      end
