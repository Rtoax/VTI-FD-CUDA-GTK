//#########################################################
//##         2D Acoustic VTI Medium Forward   
//##  Ps : P + sv wave and get rid of sv        
//##                                     Rong Tao 
/****************************
Function for VTI medium modeling,2017.2.5

 Ps:  the function of modeling following:
      
          du/dt_=1/rho*dp/dx_ , 
          dw/dt_=1/rho*dq/dz_ ,  
          dp/dt_=rho*vpx^2*du/dx_+rho*vp*vpn*dw/dz_ ,
          dq/dt_=rho*vp*vpn*du/dx_+rho*vp^2*dw/dz_ ,
                     vpx^2=vp^2*(1+2*epsilu);
                     vpn^2=vp^2*(1+2*deta);
 Copyright (C) RongTao, All right reserve.
****************************/
//########################################################
#include <stdio.h>
#include <malloc.h>
#include <math.h>
#include <stdlib.h>
#include "include/hc/cjbsegy.h"
#include "include/hc/fft.c"
#include "include/hc/alloc.c"
#include "include/hc/complex.c"

#define pi 3.141592653

/*****************func*******************/
float get_wavelet(float ts,float favg,int wtype)
 {
	float x,xx,source;

        source=0.0;
	if(wtype==1)//ricker wavelet
	{
          x=favg*ts;
          xx=x*x;
          source=(1-2*pi*pi*(xx))*exp(-(pi*pi*xx));
	}else if(wtype==2){//derivative of gaussian
          x=(-4)*favg*favg*pi*pi/log(0.1);
          source=(-2)*pi*pi*ts*exp(-x*ts*ts);
        }else if(wtype==3){//derivative of gaussian
          x=(-1)*favg*favg*pi*pi/log(0.1);
          source=exp(-x*ts*ts);
        }
        return (source);
}
/******************func********************/
void ptsource(float pfac,float xsn,float zsn,int nx,int nz,int nnx,int nnz,float dt_,float t,
              float favg,float *s,int wtype,int npd,int is,int ds)
{
float get_wavelet(float ts,float favg,int wtype);

       int i,j,ixs,izs,x,z;
       float tdelay,ts,source,fs;
      
       zero1float(s,nnx*nnz);     
       tdelay=1.0/favg;
       ts=t-tdelay;
       fs=xsn+(is-1)*ds;
       if(t<=2*tdelay)
       {
            source=get_wavelet(ts,favg,wtype);            
	    ixs = (int)(fs+0.5)+npd-1;
            izs = (int)(zsn+0.5)+npd-1;
            for(j=izs-3;j<=izs+3;j++)
	    { 
		 for(i=ixs-3;i<=ixs+3;i++)
		  {  
		    x=i-ixs;z=j-izs;
                    s[i*nnz+j]=pfac*source*exp(-z*z-x*x);
		  }
	    }
       }
}

/*******************func*********************/
void update_vel(int nx,int nz,int nnx,int nnz,int npd,int mm,float dt_,float dx_,float dz_,
           float *u0,float *w0,float *u1,float *w1,float *P,float *Q,
           float c[],float *coffx1,float *coffx2,float *coffz1,float *coffz2)
{
		 int ix,iz,im,id;
		 float dtx,dtz,xx,zz;

		 dtx=dt_/dx_;
		 dtz=dt_/dz_;
                 for(id=mm;id<nnx*nnz-mm;id++)
                 {
                   ix=id/nnz;
                   iz=id%nnz;
                   if(ix>=mm&&ix<(nnx-mm)&&iz>=mm&&iz<(nnz-mm))
                   {
                     xx=0.0;

                     zz=0.0;
	             for(im=0;im<mm;im++)
                     {
                        xx+=c[im]*(P[id+(im+1)*nnz]-P[id-im*nnz]);
                        zz+=c[im]*(Q[id+im+1]      -Q[id-im]);
                     }
                     u1[id]=coffx2[ix]*u0[id]-coffx1[ix]*dtx*xx;
                     w1[id]=coffz2[iz]*w0[id]-coffz1[iz]*dtz*zz;
                   }
                 }
}
/*******************func***********************/
void update_stress(int nx,int nz,int nnx,int nnz,float dt_,float dx_,float dz_,int mm,
            float *u1,float *w1,float *P,float *Q,float *s,float *vp,float c[],int npd,
            float *px1,float *px0,float *pz1,float *pz0,float *qx1,float *qx0,float *qz1,float *qz0,
            float *acoffx1,float *acoffx2,float *acoffz1,float *acoffz2,
            float *deta,float *epsilu,int xsn,int ds,int zsn,int is,float Circle_iso,int SV)
{
		 int i,j,ii,im,ix,iz,rx,rz,id;
		 float dtx,dtz, xx,zz;
                 int fs,ixs,izs,CR;

            float *deta1,*epsilu1;

            fs=xsn+(is-1)*ds;
            ixs=(int)(fs+0.5)+npd-1;
            izs=(int)(zsn+0.5)+npd-1;

            CR=Circle_iso;///////////////////////

            epsilu1=alloc1float(nnx*nnz);
            deta1=alloc1float(nnx*nnz);

                 dtx=dt_/dx_;
		 dtz=dt_/dz_;
                 for(id=mm;id<nnx*nnz-mm;id++)
                 {
                   ix=id/nnz;
                   iz=id%nnz;

              /** get the smooth circle to get rid of SV wave **/
                  rx=ix-ixs;
                  rz=iz-izs;
               if(SV){
                  if((rx*rx+rz*rz)<=CR*CR){
                       if((rx*rx+rz*rz)<=(CR*CR/16)){ 
                              epsilu1[id]=0.0;
                              deta1[id]=0.0;
                       }else{
                              epsilu1[id]=0.5*(1-cos(pi*((pow((rx*rx+rz*rz),0.5)-CR/4.0)*4.0/(CR*3.0-1))))*epsilu[id];
                              deta1[id]  =0.5*(1-cos(pi*((pow((rx*rx+rz*rz),0.5)-CR/4.0)*4.0/(CR*3.0-1))))*deta[id];   
                       }
                  }else{
                       epsilu1[id]=epsilu[id];
                       deta1[id]  =deta[id]; 
                  }  
               }else{
                  epsilu1[id]=epsilu[id];
                  deta1[id]  =deta[id]; 
               }  
              /** get the smooth circle to get rid of SV wave **/


                   if(ix>=mm&&ix<(nnx-mm)&&iz>=mm&&iz<(nnz-mm))
                   {
                     xx=0.0;
                     zz=0.0;
	             for(im=0;im<mm;im++)
                     {
                        xx+=c[im]*(u1[id+im*nnz]-u1[id-(im+1)*nnz]);
                        zz+=c[im]*(w1[id+im]    -w1[id-im-1]);
                     }
                     px1[id]=acoffx2[ix]*px0[id]-acoffx1[ix]*vp[id]*vp[id]*(1+2*epsilu1[id])*dtx*xx;
                     pz1[id]=acoffz2[iz]*pz0[id]-acoffz1[iz]*vp[id]*vp[id]*sqrtf(1+2*deta1[id])*dtz*zz;
                     qx1[id]=acoffx2[ix]*qx0[id]-acoffx1[ix]*vp[id]*vp[id]*sqrtf(1+2*deta1[id])*dtx*xx;
                     qz1[id]=acoffz2[iz]*qz0[id]-acoffz1[iz]*vp[id]*vp[id]*dtz*zz;

                     P[id]=px1[id]+pz1[id]+s[id];
                     Q[id]=qx1[id]+qz1[id]+s[id];
                   }
                 }
}                      
/********************func**********************/
float get_constant(float dx_,float dz_,int nx,int nz,int nnx,int nnz,int nt,int npd,float favg,float dt_,float *vp)
{
		 int i,j,id;
		 float vpmax,vpmin,H_min;
		 float dt__max,dx__max,dz__max,d0;

		 vpmax=vp[npd];
		 vpmin=vp[npd];
		 for(id=npd;id<nnx*nnz;id++)
                 {
			if(vpmax<vp[id]) vpmax=vp[id];
			if(vpmin>vp[id]) vpmin=vp[id];
                 }
		 d0=3.0*vpmax*log(100000.0)/(2.0*npd*dx_);
		 if(dx_<dz_) H_min=dx_;
		 else H_min=dz_;
/****determine time sampling interval to ensure stability***/
		 dt__max=0.5*H_min/vpmax;
                 dx__max=vpmin/favg*0.2;
                 dz__max=dx__max;

                if(dx__max<dx_)
                { 
                   printf("dx__max=%f, vpmin=%f, favg=%f \n",dx__max,vpmin,favg);
		   printf("Redefine <dx_> !\n");

                   return;
		}
                if(dz__max<dz_)
		{
		   printf("Redefine <dz_> !\n");
                   return;
		}
	        if(dt__max<dt_)
		{
                   printf("dt__max=%f, H_min=%f, vpmax=%f \n",dt__max,H_min,vpmax);
		   printf("Redefine <dt_> !\n");
                   return;
		}
             return d0;
}
/*************func*******************/
void pad_vv(int nx,int nz,int nnx,int nnz,int npd,float *ee)
{
     int ix,iz,id;
 
     for(id=0;id<nnx*nnz;id++)
     {
       ix=id/nnz;
       iz=id%nnz;
       if(ix<npd){
           ee[id]=ee[npd*nnz+iz];  //left
       }else if(ix>=nnx-npd){
           ee[id]=ee[(nnx-npd-1)*nnz+iz];//right
       }
     }
     for(id=0;id<nnx*nnz;id++)
     {
       ix=id/nnz;
       iz=id%nnz;
       if(iz<npd){
           ee[id]=ee[ix*nnz+npd];//up
       }else if(iz>=nnz-npd){
           ee[id]=ee[ix*nnz+nnz-npd-1];//down
       }
       if(ee[id]==0){printf("ee[%d][%d]==0\n",ix,iz);return;}
     }
}
/*************func*******************/
void read_file(const char FNv[],const char FNe[],const char FNd[],int nx,int nz,int nnx,int nnz,float *vv,float *epsilu,float *deta,int npd)
{
		 int i,j,id;
		
		 FILE *fp1,*fp2,*fp3;
		 if((fp1=fopen(FNv,"rb"))==NULL){printf("error open <%s>!\n",FNv);return;}
		 if((fp2=fopen(FNe,"rb"))==NULL){printf("error open <%s>!\n",FNe);return;}
		 if((fp3=fopen(FNd,"rb"))==NULL){printf("error open <%s>!\n",FNd);return;}
		 for(i=npd;i<nx+npd;i++)
		 {
			 for(j=npd;j<nz+npd;j++)
			 {
                            id=i*nnz+j;
				 fread(&vv[id],4L,1,fp1);
				 fread(&epsilu[id],4L,1,fp2);
				 fread(&deta[id],4L,1,fp3);
			 }
		 }
		 fclose(fp1);
		 fclose(fp2);
		 fclose(fp3);
}
/*************func*******************/
void initial_coffe(float dt_,float d0,int nx,int nz,
                   float *coffx1,float *coffx2,float *coffz1,float *coffz2,
                   float *acoffx1,float *acoffx2,float *acoffz1,float *acoffz2,int npd)
{		
		 int i,j;
		 for(i=0;i<npd;i++)
		 {   
			 coffx1[i]=1/(1+(dt_*d0*pow((npd-0.5-i)/npd,2))/2);
			 coffx2[i]=coffx1[i]*(1-(dt_*d0*pow((npd-0.5-i)/npd,2))/2);
			 coffz1[i]=1/(1+(dt_*d0*pow((npd-0.5-i)/npd,2))/2);

			 coffz2[i]=coffz1[i]*(1-(dt_*d0*pow((npd-0.5-i)/npd,2))/2);
		 }
		 for(i=npd+nx;i<nx+2*npd;i++)
		 {
			 coffx1[i]=1/(1+(dt_*d0*pow((0.5+i-nx-npd)/npd,2))/2);
			 coffx2[i]=coffx1[i]*(1-(dt_*d0*pow((0.5+i-nx-npd)/npd,2))/2);
		 }
		 for(i=npd+nz;i<nz+2*npd;i++)
		 {
			 coffz1[i]=1/(1+(dt_*d0*pow((0.5+i-nz-npd)/npd,2))/2);
			 coffz2[i]=coffz1[i]*(1-(dt_*d0*pow((0.5+i-nz-npd)/npd,2))/2);
		 }
		 for(i=npd;i<npd+nx;i++)
		 {
			 coffx1[i]=1.0;
			 coffx2[i]=1.0;
		 }
		 for(i=npd;i<npd+nz;i++)
		 {
			 coffz1[i]=1.0;
			 coffz2[i]=1.0;
		 }
		 for(i=0;i<npd;i++)    
		 {    
			 acoffx1[i]=1/(1+(dt_*d0*pow(((npd-i)*1.0)/npd,2))/2);
			 acoffx2[i]=coffx1[i]*(1-(dt_*d0*pow(((npd-i)*1.0)/npd,2))/2);
			 acoffz1[i]=1/(1+(dt_*d0*pow(((npd-i)*1.0)/npd,2))/2);
			 acoffz2[i]=coffz1[i]*(1-(dt_*d0*pow(((npd-i)*1.0)/npd,2))/2);
		 }
		 for(i=npd+nx;i<nx+2*npd;i++)
		 {
			 acoffx1[i]=1/(1+(dt_*d0*pow(((1+i-nx-npd)*1.0)/npd,2))/2);
			 acoffx2[i]=coffx1[i]*(1-(dt_*d0*pow(((1+i-nx-npd)*1.0)/npd,2))/2);
		 }
		 for(i=npd+nz;i<nz+2*npd;i++)
		 {
			 acoffz1[i]=1/(1+(dt_*d0*pow(((1+i-nz-npd)*1.0)/npd,2))/2);
			 acoffz2[i]=coffz1[i]*(1-(dt_*d0*pow(((1+i-nz-npd)*1.0)/npd,2))/2);
		 }

		 for(i=npd;i<npd+nx;i++)
		 {
			 acoffx1[i]=1.0;
			 acoffx2[i]=1.0;
		 }
		 for(i=npd;i<npd+nz;i++)
		 {
			 acoffz1[i]=1.0;
			 acoffz2[i]=1.0;
		 }	       
}
/*************func**************/                                                  
void cal_c(int mm,float c[])                                             
{                                                      
	if(mm==4)
	{
	c[0]=1.196289;
        c[1]=-0.0797526;
        c[2]=0.009570313;
        c[3]=-0.0006975447;
	}                                                                  
}  
/*************func**************/    
void mute_directwave(int flag_mu,int nx,int nt,float dt_,float favg,
                     float dx_,float dz_,int fs,int ds,int zs,int is,
                     float mu_v,float *p_cal,int tt)
{
  int i,j,mu_t,mu_nt;
  float mu_x,mu_z,mu_t0;

    if(flag_mu)   
     for(i=0;i<nx;i++)
       {
        mu_x=dx_*abs(i-fs-(is-1)*ds);
        mu_z=dz_*zs;
        mu_t0=sqrtf(pow(mu_x,2)+pow(mu_z,2))/mu_v;
        mu_t=(int)(2.0/(dt_/1000*favg));
        mu_nt=(int)(mu_t0/dt_*1000)+mu_t+tt;
        for(j=0;j<nt;j++)if(j<mu_nt)
           p_cal[i]=0.0;
       }else{}
}

//a########################################################################

void CPU_vti2dfd(int nx, int nz,int dx,int dz,int npd, int SV,const char FNv[],const char FNe[],const char FNd[],
                   int favg,int ns,int fs,int ds,int zs,const char FNshot[],const char FNsnap[],int nt, int dt,int run_count)
{
	int i, j, k, is, it, nnx, nnz, mm, wtype, hsx ;

	float dx_, dz_, dt_, favg_, t, d0, pfac;
	int Circle_iso, flag_mu;

       float mu_v;
       float *p_cal;

/**** ranks,wavelet,receivers,mute direct *****/
          mm=4;wtype=1;hsx=1;flag_mu=1;
/********** dat document ***********/

/********* parameters *************/
          pfac=10.0;

        dx_=(float)dx;
        dz_=(float)dz;
        favg_=(float)favg;
        dt_=(float)(dt*1.0/1000000);  


          Circle_iso=15;
/*************v***************/ 

  printf("\n##### model start #####\n");
  printf("#  nx=%2d, dx=%.2f, npd=%d\n",nx,dx_,npd);
  printf("#  nz=%2d, dz=%.2f, SV=%d\n",nz,dz_,SV);
  printf("#     vel=<%s>\n",FNv);
  printf("#  epsilu=<%s>\n",FNe);
  printf("#    deta=<%s>\n",FNd);
  printf("#  favg=%.2f\n",favg_);
  printf("#  ns=%3d\n",ns);
  printf("#  fs=%3d\n",fs);
  printf("#  ds=%3d\n",ds);
  printf("#  zs=%3d\n",zs);
  printf("#    shot=<%s>\n",FNshot);
  printf("#    snap=<%s>\n",FNsnap);


          nnx=nx+2*npd;
          nnz=nz+2*npd;
/************Loop start*************/

          FILE *fpshot,*fpsnap;
          fpshot=fopen(FNshot,"wb");
          fpsnap=fopen(FNsnap,"wb");

	  p_cal=alloc1float(nt*nx);


	   float *vp, *epsilu, *deta;
	   float *u0, *u1, *px0, *qx0, *px1, *qx1;
          float *w0, *w1, *pz0, *qz0, *pz1, *qz1;
	   float *P, *Q, *s;
	   float c[mm];

          cal_c(mm,c);

   	 vp=alloc1float(nnx*nnz); 
        epsilu=alloc1float(nnx*nnz);
        deta=alloc1float(nnx*nnz);
        read_file(FNv,FNe,FNd,nx,nz,nnx,nnz,vp,epsilu,deta,npd); 
              
/****************************/
        pad_vv(nx,nz,nnx,nnz,npd,epsilu);
        pad_vv(nx,nz,nnx,nnz,npd,deta);
        pad_vv(nx,nz,nnx,nnz,npd,vp); 
/****************************/
        mu_v=vp[npd]*sqrtf((1+2*epsilu[npd]));printf("surface vel >> %.2f\n",mu_v);

/****************************/
	 u0=alloc1float(nnx*nnz);	 u1=alloc1float(nnx*nnz);
	 w0=alloc1float(nnx*nnz);	 w1=alloc1float(nnx*nnz); 
	 P=alloc1float(nnx*nnz);      Q=alloc1float(nnx*nnz);
	 px0=alloc1float(nnx*nnz);	 px1=alloc1float(nnx*nnz);
	 pz0=alloc1float(nnx*nnz);	 pz1=alloc1float(nnx*nnz);
	 qx0=alloc1float(nnx*nnz);	 qx1=alloc1float(nnx*nnz);
	 qz0=alloc1float(nnx*nnz);	 qz1=alloc1float(nnx*nnz);
	 s=alloc1float(nnx*nnz);   

        d0=get_constant(dx_,dz_,nx,nz,nnx,nnz,nt,npd,favg,dt_,vp);
/******************************/

        float *coffx1,*coffx2,*coffz1,*coffz2,*acoffx1,*acoffx2,*acoffz1,*acoffz2;
        coffx1=alloc1float(nnx);        coffx2=alloc1float(nnx);
	 coffz1=alloc1float(nnz);        coffz2=alloc1float(nnz); 
	 acoffx1=alloc1float(nnx);	acoffx2=alloc1float(nnx);
	 acoffz1=alloc1float(nnz);	acoffz2=alloc1float(nnz);

        initial_coffe(dt_,d0,nx,nz,coffx1,coffx2,coffz1,coffz2,acoffx1,acoffx2,acoffz1,acoffz2,npd);

/**********zero************/  

        printf("--------------------------------------------------------\n");
        printf("---   \n");                                                     
/**********IS Loop start*******/
   for(is=1;is<=ns;is++)	
    {     
         printf("---   IS========%d  \n",is);
           zero1float(p_cal,nt*nx);

	   zero1float(u0,nnx*nnz);        zero1float(u1,nnx*nnz); 
           zero1float(w0,nnx*nnz);        zero1float(w1,nnx*nnz); 
           zero1float(P,nnx*nnz);         zero1float(Q,nnx*nnz); 
           zero1float(px0,nnx*nnz);       zero1float(px1,nnx*nnz); 
           zero1float(pz0,nnx*nnz);       zero1float(pz1,nnx*nnz); 
           zero1float(qx0,nnx*nnz);       zero1float(qx1,nnx*nnz); 
           zero1float(qz0,nnx*nnz);       zero1float(qz1,nnx*nnz); 

     for(it=0,t=dt_;it<nt;it++,t+=dt_)
     { 
       
      if(it%100==0)printf("---   is===%d   it===%d\n",is,it);

	ptsource(pfac,fs,zs,nx,nz,nnx,nnz,dt_,t,favg,s,wtype,npd,is,ds);
        update_vel(nx,nz,nnx,nnz,npd,mm,dt_,dx_,dz_,u0,w0,u1,w1,P,Q,c,coffx1,coffx2,coffz1,coffz2);
        update_stress(nx,nz,nnx,nnz,dt_,dx_,dz_,mm,u1,w1,P,Q,s,vp,c,npd,px1,px0,pz1,pz0,qx1,qx0,qz1,qz0,
                      acoffx1,acoffx2,acoffz1,acoffz2,deta,epsilu,fs,ds,zs,is,Circle_iso,SV);
       
	  for(i=npd;i<npd+nx;i++)  
	  {   
		p_cal[it+nt*(i-npd)]=P[npd+(nz+2*npd)*i]+P[npd+(nz+2*npd)*i];

	  }  


		for(i=0;i<nnx*nnz;i++)
		{
			u0[i]=u1[i];     w0[i]=w1[i];
			px0[i]=px1[i];   pz0[i]=pz1[i];
                        qx0[i]=qx1[i];   qz0[i]=qz1[i];
		}

           if((is==1)&&(it%50==0))
           {
              fseek(fpsnap,(int)(it/50)*(nnx)*(nnz)*4L,0);
              fwrite(P,4L,nnx*nnz,fpsnap);
           }
     }//it loop end
    fseek(fpshot,(is-1)*nx*nt*4L,0);
    fwrite(p_cal,4L,nx*nt,fpshot);
    } 


/*********IS Loop end*********/ 		     
   printf("---   The forward is over    \n"); 
   printf("---   Complete!!!!!!!!! \n");  

   fclose(fpshot);
   free1float(p_cal);
/***********close************/ 
          fclose(fpsnap);
/***********free*************/        
          free1float(coffx1);free1float(coffx2);
          free1float(coffz1);free1float(coffz2);
          free1float(acoffx1);free1float(acoffx2);
          free1float(acoffz1);free1float(acoffz2);

          free1float(u0);   free1float(u1);  
          free1float(w0);   free1float(w1);

          free1float(P);  free1float(Q);

          free1float(px0);  free1float(px1);  free1float(pz0);  free1float(pz1);
          free1float(qx0);  free1float(qx1);  free1float(qz0);  free1float(qz1);

          free1float(s);
}

