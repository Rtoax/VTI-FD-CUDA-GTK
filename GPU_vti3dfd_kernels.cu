//a#########################################################
//a##         3D Acoustic VTI Medium Forward 
//a##    
//a##  Ps :GPU(CUDA)  
//a##
//a##/*a***************************
//a##Function for VTI medium modeling,
//a##
//a## Ps:  the function of modeling following:
//a##      
//a##          du/dt_=1/rho*dp/dx_ , 
//a##          dv/dt_=1/rho*dp/dy_ , 
//a##          dw/dt_=1/rho*dq/dz_ ,  
//a##          dp/dt_=rho*vpx^2*(du/dx_+dv/dy_)+rho*vp*vpn*dw/dz_ ,
//a##          dq/dt_=rho*vp*vpn*(du/dx_+dv/dy_)+rho*vp^2*dw/dz_ ,
//a##                     vpx^2=vp^2*(1+2*epsilu);
//a##                     vpn^2=vp^2*(1+2*deta);
//a##  
//a##*********a*******************/
//a##
//a##                                     Rong Tao 
//a##                            
//a#########################################################
#include<stdio.h>
#include<malloc.h>
#include<math.h>
#include<stdlib.h>
#include <string.h>
#include <cuda_runtime.h>

#define pi 3.141592653

#define BlockSize1 16// tile size in 1st-axis
#define BlockSize2 16// tile size in 2nd-axis

#define mm 4

__device__ float d0;

__constant__ float c[mm]={1.196289,-0.0797526,0.009570313,-0.0006975447};

//a################################################################################
void check_gpu_error3d (const char *msg) 
/*< check GPU errors >*/
{
    cudaError_t err = cudaGetLastError ();
    if (cudaSuccess != err) { 
	printf("Cuda error: %s: %s\n", msg, cudaGetErrorString (err)); 
	exit(0);   
    }
}
//a################################################################################
__global__ void add_source3d(float pfac,int fsx,int fsy,int fsz,int nx,int ny,int nz,int nnx,int nny,int nnz,float dt_,float t,
                        float favg_,int wtype,int npml,int is,int dsx,int dsy,int dsz,float *P,float *Q)
/*< generate ricker wavelet with time deley >*/
{
       int ixs,iys,izs;
       float x_,xx_,tdelay,ts,source=0.0,sx,sy,sz; 
  
       tdelay=1.0/favg_;
       ts=t-tdelay;

       sx=fsx+is*dsx;
       sy=fsy+is*dsy;
       sz=fsz+is*dsz;

	if(wtype==1)//ricker wavelet
	{
          x_=favg_*ts;
          xx_=x_*x_;
          source=(1-2*pi*pi*(xx_))*exp(-(pi*pi*xx_));
	}else if(wtype==2){//derivative of gaussian
          x_=(-4)*favg_*favg_*pi*pi/log(0.1);
          source=(-2)*pi*pi*ts*exp(-x_*ts*ts);
        }else if(wtype==3){//derivative of gaussian
          x_=(-1)*favg_*favg_*pi*pi/log(0.1);
          source=exp(-x_*ts*ts);
        }

       if(t<=2*tdelay)
       {         
	     ixs = sx+npml-1;
	     iys = sy+npml-1;
            izs = sz+npml-1;
            P[izs+ixs*nnz+iys*nnz*nnx]+=pfac*source;
            Q[izs+ixs*nnz+iys*nnz*nnx]+=pfac*source;
       }
}
/*******************func*********************/
__global__ void update_vel3d(int nx,int ny,int nz,int nnx,int nny,int nnz,int npml,float dt_,float dx_,float dy_,float dz_,
                           float *u0,float *v0,float *w0,float *u1,float *v1,float *w1,float *P,float *Q,
                           float *coffx1,float *coffx2,float *coffy1,float *coffy2,float *coffz1,float *coffz2)
{
    const int iz = blockIdx.x * blockDim.x + threadIdx.x;//0--nz's thread:iz
    const int ix = blockIdx.y * blockDim.y + threadIdx.y;//0--nx's thread:ix

       int id,iy,im;
	float dtx,dty,dtz,xx,yy,zz;

		 dtx=dt_/dx_;
		 dty=dt_/dy_;
		 dtz=dt_/dz_;

       for(iy=0;iy<nny;iy++)
        {
               id=iz+ix*nnz+iy*nnz*nnx;
               if(id>=mm&&id<nnx*nny*nnz-mm)
                 {
                   if(ix>=mm&&ix<(nnx-mm)&&iy>=mm&&iy<(nny-mm)&&iz>=mm&&iz<(nnz-mm))
                    {
                     xx=0.0;
                     yy=0.0;
                     zz=0.0;
	             for(im=0;im<mm;im++)
                      {
                        yy+=c[im]*(P[id+(im+1)*nnz*nnx] - P[id-im*nnz*nnx]);
                        xx+=c[im]*(P[id+(im+1)*nnz]     - P[id-im*nnz]);
                        zz+=c[im]*(Q[id+im+1]           - Q[id-im]);
                      }
                     u1[id]=coffx2[ix]*u0[id]-coffx1[ix]*dtx*xx;
                     v1[id]=coffy2[iy]*v0[id]-coffy1[iy]*dty*yy;
                     w1[id]=coffz2[iz]*w0[id]-coffz1[iz]*dtz*zz;
                   }
                 }
        }  



}
/*******************func***********************/
__global__ void update_stress3d(int nx,int ny,int nz,int nnx,int nny,int nnz,float dt_,float dx_,float dy_,float dz_,
                           float *u1,float *v1,float *w1,float *P,float *Q,float *vp,int npml,
                           float *px1,float *px0,float *py1,float *py0,float *pz1,float *pz0,
                           float *qx1,float *qx0,float *qy1,float *qy0,float *qz1,float *qz0,
                           float *acoffx1,float *acoffx2,float *acoffy1,float *acoffy2,float *acoffz1,float *acoffz2,
                           float *deta,float *epsilu,int fsx,int dsx,int fsy,int dsy,int fsz,int dsz,int is,int SV)
{
    const int iz = blockIdx.x * blockDim.x + threadIdx.x;//0--nz's thread:iz
    const int ix = blockIdx.y * blockDim.y + threadIdx.y;//0--nx's thread:ix

       int id,iy,im,rx,ry,rz,R=15,r=4;
	float dtx,dty,dtz,xx,yy,zz,ee,dd;

		 dtx=dt_/dx_;
		 dty=dt_/dy_;
		 dtz=dt_/dz_;

       for(iy=0;iy<nny;iy++)
        {
               id=iz+ix*nnz+iy*nnz*nnx;
               if(id>=mm&&id<nnx*nnz*nny-mm)
                 {
/************************i****************************************/
/************************iso circle start*************************/
                   rx=ix-(fsx+is*dsx+npml-1);
                   ry=iy-(fsy+is*dsy+npml-1);
                   rz=iz-(fsz+is*dsz+npml-1);
                   if(SV){
                       if((rx*rx+ry*ry+rz*rz)<=R*R){
                           if((rx*rx+ry*ry+rz*rz)<=r*r){
                               ee = 0.0;
                               dd = 0.0;
                           }else{
                               ee = 0.5*(1-cos(pi*((sqrtf(rx*rx+ry*ry+rz*rz)-r)*4.0/(R*3.0-1))))*epsilu[id];
                               dd = 0.5*(1-cos(pi*((sqrtf(rx*rx+ry*ry+rz*rz)-r)*4.0/(R*3.0-1))))*deta[id]; 
                              }
                       }else{
                          ee=epsilu[id];
                          dd=deta[id];
                          }
                   }else{
                      ee=epsilu[id];
                      dd=deta[id];
                     }
/************************ iso circle end *************************/
/************************i****************************************/
                   if(ix>=mm&&ix<(nnx-mm)&&iy>=mm&&iy<(nny-mm)&&iz>=mm&&iz<(nnz-mm))
                     {
                     xx=0.0;
                     yy=0.0;
                     zz=0.0;
	             for(im=0;im<mm;im++)
                       {
                        yy+=c[im]*(v1[id+im*nnz*nnx] - v1[id-(im+1)*nnz*nnx]);
                        xx+=c[im]*(u1[id+im*nnz]     - u1[id-(im+1)*nnz]);
                        zz+=c[im]*(w1[id+im]         - w1[id-im-1]);
                       }
                     px1[id]=acoffx2[ix]*px0[id] - acoffx1[ix]*vp[id]*vp[id]*(1+2*ee)*dtx*xx;
                     py1[id]=acoffy2[iy]*py0[id] - acoffy1[iy]*vp[id]*vp[id]*(1+2*ee)*dty*yy;
                     pz1[id]=acoffz2[iz]*pz0[id] - acoffz1[iz]*vp[id]*vp[id]*sqrtf(1+2*dd)*dtz*zz;

                     qx1[id]=acoffx2[ix]*qx0[id] - acoffx1[ix]*vp[id]*vp[id]*sqrtf(1+2*dd)*dtx*xx;
                     qy1[id]=acoffy2[iy]*qy0[id] - acoffy1[iy]*vp[id]*vp[id]*sqrtf(1+2*dd)*dty*yy;
                     qz1[id]=acoffz2[iz]*qz0[id] - acoffz1[iz]*vp[id]*vp[id]*dtz*zz;

                     P[id]=px1[id]+py1[id]+pz1[id];
                     Q[id]=qx1[id]+qy1[id]+qz1[id];
                   }
                 }
         }
}                      
/********************func**********************/
__global__ void get_d03d(float dx_,float dy_,float dz_,int nnx,int nny,int nnz,int npml,float *vp)
{
   d0=10.0*vp[nny*nnx*nnz/2]*log(100000.0)/(2.0*npml*((dx_+dy_+dz_)/3.0));
}
/*************func*******************/
void pad_vv3d(int nx,int ny,int nz,int nnx,int nny,int nnz,int npml,float *ee)
{
     int ix,iy,iz,id;
 
	    for(iy=0;iy<nny;iy++)
		 for(ix=0;ix<nnx;ix++)
		 {
			 for(iz=0;iz<nnz;iz++)
			 {
                             id=iz+ix*nnz+iy*nnz*nnx;

                             if(ix<npml){
                                ee[id]=ee[iz+npml*nnz+iy*nnz*nnx];  //left
                             }else if(ix>=nnx-npml){
                                ee[id]=ee[iz+(nnx-npml-1)*nnz+iy*nnz*nnx];//right
                                 }
			 }
		 }
	    for(iy=0;iy<nny;iy++)
		 for(ix=0;ix<nnx;ix++)
		 {
			 for(iz=0;iz<nnz;iz++)
			 {
                             id=iz+ix*nnz+iy*nnz*nnx;

                             if(iy<npml){
                                ee[id]=ee[iz+ix*nnz+npml*nnz*nnx];  //front
                             }else if(iy>=nny-npml){
                                ee[id]=ee[iz+ix*nnz+(nny-npml-1)*nnz*nnx];//back
                                 }
			 }
		 }
	    for(iy=0;iy<nny;iy++)
		 for(ix=0;ix<nnx;ix++)
		 {
			 for(iz=0;iz<nnz;iz++)
			 {
                             id=iz+ix*nnz+iy*nnz*nnx;

                             if(iz<npml){
                                ee[id]=ee[npml+ix*nnz+iy*nnz*nnx];  //up
                             }else if(iz>=nnz-npml){
                                ee[id]=ee[nnz-npml-1+ix*nnz+iy*nnz*nnx];//down
                                 }
			 }
		 }

}
/*************func*******************/
void read_file3d(const char FNv[],const char FNe[],const char FNd[],int nx,int ny,int nz,
               int nnx,int nny,int nnz,float *vv,float *epsilu,float *deta,int npml)
{
		 int ix,iy,iz,id;
		
		 FILE *fp1,*fp2,*fp3;
		 if((fp1=fopen(FNv,"rb"))==NULL)printf("error open <%s>!\n",FNv);
		 if((fp2=fopen(FNe,"rb"))==NULL)printf("error open <%s>!\n",FNe);
		 if((fp3=fopen(FNd,"rb"))==NULL)printf("error open <%s>!\n",FNd);

	    for(iy=npml;iy<ny+npml;iy++)
		 for(ix=npml;ix<nx+npml;ix++)
		 {
			 for(iz=npml;iz<nz+npml;iz++)
			 {
                             id=iz+ix*nnz+iy*nnz*nnx;
				 fread(&vv[id],4L,1,fp1);//vv[id]=3000.0;
				 fread(&epsilu[id],4L,1,fp2);
				 fread(&deta[id],4L,1,fp3);
			 }
		 }
		 fclose(fp1);
		 fclose(fp2);
		 fclose(fp3);
}
/*************func*******************/
__global__ void initial_coffe3d(float dt_,int nn,float *coff1,float *coff2,float *acoff1,float *acoff2,int npml)
{		
	 int id=threadIdx.x+blockDim.x*blockIdx.x;

           if(id<nn+2*npml)
            {
		 if(id<npml)
		 {   
			 coff1[id]=1.0/(1.0+(dt_*d0*pow((npml-0.5-id)/npml,2.0))/2.0);
			 coff2[id]=coff1[id]*(1.0-(dt_*d0*pow((npml-0.5-id)/npml,2.0))/2.0);

			 acoff1[id]=1.0/(1.0+(dt_*d0*pow(((npml-id)*1.0)/npml,2.0))/2.0);
			 acoff2[id]=acoff1[id]*(1.0-(dt_*d0*pow(((npml-id)*1.0)/npml,2.0))/2.0);

		 }else if(id>=npml&&id<npml+nn){

			 coff1[id]=1.0;
			 coff2[id]=1.0;

			 acoff1[id]=1.0;
			 acoff2[id]=1.0;

		 }else{

			 coff1[id]=1.0/(1.0+(dt_*d0*pow((0.5+id-nn-npml)/npml,2.0))/2.0);
			 coff2[id]=coff1[id]*(1.0-(dt_*d0*pow((0.5+id-nn-npml)/npml,2.0))/2.0);

			 acoff1[id]=1.0/(1.0+(dt_*d0*pow(((id-nn-npml)*1.0)/npml,2.0))/2.0);
			 acoff2[id]=acoff1[id]*(1.0-(dt_*d0*pow(((id-nn-npml)*1.0)/npml,2.0))/2.0);
		 }	
            }       
}
/*************func*******************/
__global__ void shot_record3d(int nnx,int nny, int nnz, int nx,int ny, int nz, int npml, int it, int nt, float *P, float *shot)
{		
	 int id=threadIdx.x+blockDim.x*blockIdx.x;

        int ix=id%nx;
        int iy=id/nx;

           if(id<nx*ny)
            {
               shot[it+nt*ix+nt*nx*iy]=P[npml+nnz*(ix+npml)+nnz*nnx*(iy+npml)];
            }       
}
/*************func**************/ 
void window3d(float *a, float *b, int nz, int nx, int ny, int nnz, int nnx, int npml)
/*< window a 3d subvolume >*/
{
	int iz, ix, iy;
	
	for(iy=0; iy<ny; iy++)
	for(ix=0; ix<nx; ix++)
	for(iz=0; iz<nz; iz++)
	{
		a[iz+nz*ix+nz*nx*iy]=b[(iz+npml)+nnz*(ix+npml)+nnz*nnx*(iy+npml)];
	}
}
/*************func**************/    
__global__ void mute_directwave3d(int nx,int ny,int nt,float dt_,float favg_, float dx_,float dy_,float dz_,int fsx,int fsy,int dsx,int dsy,
                                int fsz,int is, float *vp,float *epsilu,float *shot,int tt)
{

    const int ix = blockIdx.x * blockDim.x + threadIdx.x;
    const int iy = blockIdx.y * blockDim.y + threadIdx.y;

    int id,it;
    int mu_t,mu_nt;
    float mu_x,mu_y,mu_z,mu_t0;

       for(it=0;it<nt;it++)
        {
          id=it+ix*nt+iy*nx*nt;
          if(ix<nx&&iy<ny&&it<nt)
            {
              mu_x=dx_*abs(ix-fsx-(is)*dsx);
              mu_y=dy_*abs(iy-fsy-(is)*dsy);
              mu_z=dz_*fsz;
              mu_t0=sqrtf(pow(mu_x,2)+pow(mu_y,2)+pow(mu_z,2))/(vp[1]*sqrtf(1+2*epsilu[1]));
              mu_t=(int)(2.0/(dt_*favg_));
              mu_nt=(int)(mu_t0/dt_)+mu_t+tt;

                 if(it<mu_nt)
                    shot[id]=0.0;
            }
        }
}
//a########################################################################
extern "C"  void GPU_vti3dfd(int nx, int ny, int nz,int dx,int dy,int dz,int npml,int SV,
           const char FNv[],const char FNe[],const char FNd[],
           int favg,int ns,int fsx,int dsx,int fsy,int dsy,int fsz,int dsz,
           const char FNshot[],const char FNsnap[],int nt, int dt,int run_count)
{
	int is, it, nnx, nny, nnz,  wtype;
	float dx_, dy_, dz_, dt_, t, pfac, favg_;

	float *v, *e, *d;
	float *vp, *epsilu, *deta;
	float *s_u0, *s_u1, *s_px0, *s_qx0, *s_px1, *s_qx1;
	float *s_v0, *s_v1, *s_py0, *s_qy0, *s_py1, *s_qy1;
       float *s_w0, *s_w1, *s_pz0, *s_qz0, *s_pz1, *s_qz1;
	float *s_P, *s_Q, *shot_Dev, *shot_Hos;

       float *coffx1,*coffx2,*coffy1,*coffy2,*coffz1,*coffz2;
       float *acoffx1,*acoffx2,*acoffy1,*acoffy2,*acoffz1,*acoffz2;

       clock_t start, end;
/*************wavelet\boundary**************/
          wtype=1;
/********** dat document ***********/

/********aaa************/  
	 FILE *fpsnap, *fpshot;
        fpshot=fopen(FNshot,"wb");
        fpsnap=fopen(FNsnap,"wb");

 
/********* parameters *************/

     pfac=10.0;
  
       dx_=(float)dx;
       dy_=(float)dy;
       dz_=(float)dz;
       favg_=(float)favg;
       dt_=(float)(dt*1.0/1000000);
        
/*************v***************/ 
          nnx=nx+2*npml;
          nny=ny+2*npml;
          nnz=nz+2*npml;
/************a*************/
  printf("\n##### model start #####\n");
  printf("#  nx=%2d, dx=%.2f, npd=%d\n",nx,dx_,npml);
  printf("#  ny=%2d, dy=%.2f, \n",ny,dy_);
  printf("#  nz=%2d, dz=%.2f, SV=%d\n",nz,dz_,SV);
  printf("#     vel=<%s>\n",FNv);
  printf("#  epsilu=<%s>\n",FNe);
  printf("#    deta=<%s>\n",FNd);
  printf("#  favg=%.2f\n",favg_);
  printf("#  ns=%3d\n",ns);
  printf("#  fsx=%3d, fsy=%3d, fsz=%3d, \n",fsx,fsy,fsz);
  printf("#  dsx=%3d, dsy=%3d, dsz=%3d, \n",dsx,dsy,dsz);
  printf("#    shot=<%s>\n",FNshot);
  printf("#    snap=<%s>\n",FNsnap);

    	 v=(float*)malloc(nnz*nnx*nny*sizeof(float));
    	 e=(float*)malloc(nnz*nnx*nny*sizeof(float));
    	 d=(float*)malloc(nnz*nnx*nny*sizeof(float));
    	 shot_Hos=(float*)malloc(nt*nx*ny*sizeof(float));
        read_file3d(FNv,FNe,FNd,nx,ny,nz,nnx,nny,nnz,v,e,d,npml);
/****************************/
        pad_vv3d(nx,ny,nz,nnx,nny,nnz,npml,e);
        pad_vv3d(nx,ny,nz,nnx,nny,nnz,npml,d);
        pad_vv3d(nx,ny,nz,nnx,nny,nnz,npml,v);

        cudaSetDevice(0);// initialize device, default device=0;
	 if(run_count==0)check_gpu_error3d("Failed to initialize device!");

	dim3 Xdimg, dimg, dimb;
	Xdimg.x=(nnx+BlockSize1-1)/BlockSize1;
	Xdimg.y=(nny+BlockSize2-1)/BlockSize2;
	dimg.x=(nnz+BlockSize1-1)/BlockSize1;
	dimg.y=(nnx+BlockSize2-1)/BlockSize2;
	dimb.x=BlockSize1;
	dimb.y=BlockSize2;
/****************************/
        cudaMalloc(&vp, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&epsilu, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&deta, nnz*nnx*nny*sizeof(float));
	 cudaMemcpy(vp, v, nnz*nnx*nny*sizeof(float), cudaMemcpyHostToDevice);
	 cudaMemcpy(epsilu, e, nnz*nnx*nny*sizeof(float), cudaMemcpyHostToDevice);
	 cudaMemcpy(deta, d, nnz*nnx*nny*sizeof(float), cudaMemcpyHostToDevice);
/****************************/
        cudaMalloc(&s_u0, nnz*nnx*nny*sizeof(float));    cudaMalloc(&s_u1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_v0, nnz*nnx*nny*sizeof(float));    cudaMalloc(&s_v1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_w0, nnz*nnx*nny*sizeof(float));    cudaMalloc(&s_w1, nnz*nnx*nny*sizeof(float));

        cudaMalloc(&s_P, nnz*nnx*nny*sizeof(float));     cudaMalloc(&s_Q, nnz*nnx*nny*sizeof(float));

        cudaMalloc(&s_px0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_px1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_py0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_py1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_pz0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_pz1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_qx0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_qx1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_qy0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_qy1, nnz*nnx*nny*sizeof(float));
        cudaMalloc(&s_qz0, nnz*nnx*nny*sizeof(float));   cudaMalloc(&s_qz1, nnz*nnx*nny*sizeof(float));

        cudaMalloc(&coffx1, nnx*sizeof(float));     cudaMalloc(&coffx2, nnx*sizeof(float));
        cudaMalloc(&coffy1, nnx*sizeof(float));     cudaMalloc(&coffy2, nnx*sizeof(float));
        cudaMalloc(&coffz1, nnz*sizeof(float));     cudaMalloc(&coffz2, nnz*sizeof(float));
        cudaMalloc(&acoffx1, nnx*sizeof(float));    cudaMalloc(&acoffx2, nnx*sizeof(float));
        cudaMalloc(&acoffy1, nnx*sizeof(float));    cudaMalloc(&acoffy2, nnx*sizeof(float));
        cudaMalloc(&acoffz1, nnz*sizeof(float));    cudaMalloc(&acoffz2, nnz*sizeof(float));

        cudaMalloc(&shot_Dev, nx*ny*nt*sizeof(float));
/******************************/
	 if(run_count==0)check_gpu_error3d("Failed to allocate memory for variables!");

        get_d03d<<<1, 1>>>(dx_,dy_,dz_,nnx,nny,nnz,npml,vp);
        initial_coffe3d<<<(nnx+511)/512, 512>>>(dt_,nx,coffx1,coffx2,acoffx1,acoffx2,npml);
        initial_coffe3d<<<(nny+511)/512, 512>>>(dt_,ny,coffy1,coffy2,acoffy1,acoffy2,npml);
        initial_coffe3d<<<(nnz+511)/512, 512>>>(dt_,nz,coffz1,coffz2,acoffz1,acoffz2,npml);



        printf("--------------------------------------------------------\n");
        printf("---   \n");   
        start = clock();                                  
/**********IS Loop start*******/
   for(is=0;is<ns;is++)	
    {     
       //  printf("---   IS=%3d  \n",is);

     cudaMemset(s_u0, 0, nnz*nnx*nny*sizeof(float));     cudaMemset(s_u1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_v0, 0, nnz*nnx*nny*sizeof(float));     cudaMemset(s_v1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_w0, 0, nnz*nnx*nny*sizeof(float));     cudaMemset(s_w1, 0, nnz*nnx*nny*sizeof(float));

     cudaMemset(s_P, 0, nnz*nnx*nny*sizeof(float));      cudaMemset(s_Q, 0, nnz*nnx*nny*sizeof(float));

     cudaMemset(s_px0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_px1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_py0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_py1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_pz0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_pz1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_qx0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_qx1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_qy0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_qy1, 0, nnz*nnx*nny*sizeof(float));
     cudaMemset(s_qz0, 0, nnz*nnx*nny*sizeof(float));    cudaMemset(s_qz1, 0, nnz*nnx*nny*sizeof(float));

     cudaMemset(shot_Dev, 0, nt*nx*ny*sizeof(float));

     for(it=0,t=dt_;it<nt;it++,t+=dt_)
     { 
      if(it%100==0)printf("---   IS===%d   it===%d\n",is,it);
        add_source3d<<<1,1>>>(pfac,fsx,fsy,fsz,nx,ny,nz,nnx,nny,nnz,dt_,t,favg_,wtype,npml,is,dsx,dsy,dsz,s_P,s_Q);
        update_vel3d<<<dimg,dimb>>>(nx,ny,nz,nnx,nny,nnz,npml,dt_,dx_,dy_,dz_,
                                 s_u0,s_v0,s_w0,s_u1,s_v1,s_w1,s_P,s_Q,coffx1,coffx2,coffy1,coffy2,coffz1,coffz2);
        update_stress3d<<<dimg,dimb>>>(nx,ny,nz,nnx,nny,nnz,dt_,dx_,dy_,dz_,s_u1,s_v1,s_w1,s_P,s_Q,vp,npml,
                                     s_px1,s_px0,s_py1,s_py0,s_pz1,s_pz0,s_qx1,s_qx0,s_qy1,s_qy0,s_qz1,s_qz0,
                                     acoffx1,acoffx2,acoffy1,acoffy2,acoffz1,acoffz2,deta,epsilu, 
                                     fsx, dsx, fsy, dsy,fsz,dsz, is, SV);
        s_u0=s_u1; s_v0=s_v1; s_w0=s_w1; s_px0=s_px1; s_py0=s_py1; s_pz0=s_pz1; s_qx0=s_qx1; s_qy0=s_qy1; s_qz0=s_qz1; 

        shot_record3d<<<(nx*ny+511)/512, 512>>>(nnx,nny, nnz, nx,ny, nz, npml, it, nt, s_P, shot_Dev);


           if((is==0)&&(it!=0&&it%300==0))
            {
	       cudaMemcpy(e, s_P, nnz*nnx*nny*sizeof(float), cudaMemcpyDeviceToHost);
              fseek(fpsnap,(int)(it/300-1)*(nx*ny*nz)*4L,0);
              window3d(v, e, nz, nx, ny, nnz, nnx, npml);
              fwrite(v,4L,nx*nz*ny,fpsnap);
            }
     }//it loop end
      mute_directwave3d<<<Xdimg,dimb>>>(nx,ny,nt,dt_,favg_,dx_,dy_,dz_,fsx,fsy,dsx,dsy,fsz,is,vp,epsilu,shot_Dev,100);
      cudaMemcpy(shot_Hos, shot_Dev, nt*nx*ny*sizeof(float), cudaMemcpyDeviceToHost);
      fseek(fpshot,is*nt*nx*ny*sizeof(float),0);
      fwrite(shot_Hos,sizeof(float),nt*nx*ny,fpshot);

    }//is loop end
    end = clock();
/*********IS Loop end*********/ 		     
   printf("---   The forward is over    \n"); 
   printf("---   Complete!!!!!!!!! \n");  
   printf("total %d shots: %f (s)\n", ns, ((float)(end-start))/CLOCKS_PER_SEC);



/***********close************/ 
          fclose(fpsnap);   fclose(fpshot);
/***********free*************/ 
       cudaFree(coffx1);       cudaFree(coffx2);
       cudaFree(coffz1);       cudaFree(coffz2);
       cudaFree(acoffx1);      cudaFree(acoffx2);
       cudaFree(acoffz1);      cudaFree(acoffz2);

       cudaFree(s_u0);           cudaFree(s_u1);
       cudaFree(s_v0);           cudaFree(s_v1);
       cudaFree(s_w0);           cudaFree(s_w1);

       cudaFree(s_P);            cudaFree(s_Q);

       cudaFree(s_px0);          cudaFree(s_px1);
       cudaFree(s_py0);          cudaFree(s_py1);
       cudaFree(s_pz0);          cudaFree(s_pz1);
       cudaFree(s_qx0);          cudaFree(s_qx1);
       cudaFree(s_qy0);          cudaFree(s_qy1);
       cudaFree(s_qz0);          cudaFree(s_qz1);

       cudaFree(shot_Dev);
/***************host free*****************/
	free(v);	free(e);	free(d);
       free(shot_Hos);
}

