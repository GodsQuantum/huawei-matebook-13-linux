#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <openssl/evp.h>
#include "../../driver/goodix51a0/gx51_factory_pmk.h"

static const uint8_t seed[16] = {
  0x5c,0xba,0x6e,0x25,0x81,0x95,0x18,0xde,
  0x2d,0x53,0xe9,0x6d,0xc0,0x34,0x7a,0xb0
};
static const uint32_t bases[3] = {0x08004000u,0x08008000u,0x0800a000u};

static void sha256(const uint8_t *p,size_t n,uint8_t out[32]) {
  unsigned int len=0;
  assert(EVP_Digest(p,n,out,&len,EVP_sha256(),NULL)==1 && len==32);
}

static size_t make_body(uint8_t body[256],const uint8_t pmk[48]) {
  uint8_t salt[16],kdf[80],key[32],pt[240],ct[240];
  for(size_t i=0;i<16;i++) salt[i]=(uint8_t)(0x40+i);
  memcpy(kdf,salt,16); memset(kdf+16,0,48); memcpy(kdf+64,seed,16); sha256(kdf,80,key);
  memset(pt,0,sizeof pt); pt[0]=0; pt[1]=0x0d; pt[5]=0x30; memcpy(pt+6,pmk,48);
  EVP_CIPHER_CTX *ctx=EVP_CIPHER_CTX_new(); int a=0,b=0; assert(ctx);
  assert(EVP_EncryptInit_ex(ctx,EVP_aes_128_cbc(),NULL,key,salt)==1); EVP_CIPHER_CTX_set_padding(ctx,0);
  assert(EVP_EncryptUpdate(ctx,ct,&a,pt,sizeof pt)==1); assert(EVP_EncryptFinal_ex(ctx,ct+a,&b)==1); assert(a+b==240);
  EVP_CIPHER_CTX_free(ctx); memcpy(body,salt,16); memcpy(body+16,ct,240); return 256;
}

typedef struct {
  uint8_t body[3][256];
  unsigned valid_mask;
  int mem_calls;
} FakeFactory;

static bool fake_mem(void *user,uint32_t address,uint32_t len,uint8_t *out) {
  FakeFactory *f=user; f->mem_calls++;
  for(unsigned i=0;i<3;i++) {
    if (!(f->valid_mask & (1u<<i))) continue;
    if (address==bases[i]+8u && len==80u) {
      memcpy(out,f->body[i],80); out[0]^=(uint8_t)(0x31u+0x10u*i); return true;
    }
  }
  return false;
}

typedef struct {
  uint8_t staging[GXFP_FACTORY_STAGING_LEN];
  unsigned calls;
  bool corrupt_tail;
} FakeStaging;

static bool fake_staging(void *user,uint32_t selector,uint32_t request_len,
                         uint8_t *out,size_t out_cap,size_t *out_len) {
  FakeStaging *f=user;
  if (!out || !out_len || request_len!=GXFP_FACTORY_BODY_LEN ||
      out_cap<GXFP_FACTORY_STAGING_LEN ||
      (selector!=0x08004000u && selector!=0x20000000u)) return false;
  memcpy(out,f->staging,GXFP_FACTORY_STAGING_LEN);
  out[0]^=(selector==0x08004000u)?0x31u:0x71u;
  if (f->corrupt_tail && selector==0x20000000u) out[79]^=1u;
  *out_len=GXFP_FACTORY_STAGING_LEN; f->calls++; return true;
}

int main(void) {
  uint8_t pmk[48],got[48],body[256];
  for(size_t i=0;i<48;i++) pmk[i]=(uint8_t)(0x20+i);
  size_t n=make_body(body,pmk);
  assert(n==GXFP_FACTORY_BODY_LEN);
  assert(gxfp_factory_pmk_decrypt(body,n,got));
  assert(memcmp(got,pmk,48)==0);
  assert(gxfp_factory_pmk_decrypt(body,80,got));
  assert(memcmp(got,pmk,48)==0);

  {
    uint8_t damaged[256], recovered=0;
    memcpy(damaged,body,n); damaged[0]^=0x55;
    assert(gxfp_factory_pmk_recover_first_byte(damaged,n,&recovered,got));
    assert(recovered==body[0]); assert(memcmp(got,pmk,48)==0);
  }

  {
    FakeFactory f={0}; uint8_t loaded[48];
    for(unsigned i=0;i<3;i++) memcpy(f.body[i],body,n);
    f.body[2][32]^=1; /* one damaged redundant copy must not break 2-of-3 consensus */
    f.valid_mask=7;
    assert(gxfp_factory_load_pmk(fake_mem,&f,loaded));
    assert(memcmp(loaded,pmk,48)==0);
    assert(f.mem_calls==3);
  }
  {
    FakeFactory f={0}; uint8_t loaded[48];
    memcpy(f.body[0],body,n); f.valid_mask=1;
    assert(!gxfp_factory_load_pmk(fake_mem,&f,loaded)); /* one copy is not enough */
  }
  {
    uint8_t a[248], b[248], loaded[48];
    memcpy(a,body,sizeof a); memcpy(b,body,sizeof b);
    a[0]^=0x31; b[0]^=0x71; /* address-dependent first-byte corruption */
    assert(gxfp_factory_pmk_from_staging_pair(a,sizeof a,b,sizeof b,loaded));
    assert(memcmp(loaded,pmk,48)==0);

    b[79]^=1; /* any tail difference means the staging is not address-independent */
    assert(!gxfp_factory_pmk_from_staging_pair(a,sizeof a,b,sizeof b,loaded));
    b[79]^=1;
    assert(!gxfp_factory_pmk_from_staging_pair(a,79,b,79,loaded));
  }
  {
    FakeStaging f={0}; uint8_t loaded[48];
    memcpy(f.staging,body,sizeof f.staging);
    assert(gxfp_factory_load_pmk_from_single_staging(fake_staging,&f,loaded));
    assert(memcmp(loaded,pmk,48)==0); assert(f.calls==1);

    f.calls=0;
    assert(gxfp_factory_load_pmk_from_staging(fake_staging,&f,loaded));
    assert(memcmp(loaded,pmk,48)==0); assert(f.calls==2);
    f.calls=0; f.corrupt_tail=true;
    assert(!gxfp_factory_load_pmk_from_staging(fake_staging,&f,loaded));
    assert(f.calls==2);
  }
  body[16]^=1;
  assert(!gxfp_factory_pmk_decrypt(body,n,got));
  puts("test_factory_pmk: OK");
  return 0;
}
