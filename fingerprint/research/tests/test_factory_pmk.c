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

static void sha256(const uint8_t *p,size_t n,uint8_t out[32]) {
  unsigned int len=0;
  assert(EVP_Digest(p,n,out,&len,EVP_sha256(),NULL)==1 && len==32);
}

static size_t make_body(uint8_t body[80],const uint8_t pmk[48]) {
  uint8_t salt[16],kdf[80],key[32],pt[64],ct[64];
  for(size_t i=0;i<16;i++) salt[i]=(uint8_t)(0x40+i);
  memcpy(kdf,salt,16); memset(kdf+16,0,48); memcpy(kdf+64,seed,16); sha256(kdf,80,key);
  memset(pt,0,sizeof pt); pt[0]=0; pt[1]=0x0d; pt[5]=0x30; memcpy(pt+6,pmk,48);
  EVP_CIPHER_CTX *ctx=EVP_CIPHER_CTX_new(); int a=0,b=0; assert(ctx);
  assert(EVP_EncryptInit_ex(ctx,EVP_aes_128_cbc(),NULL,key,salt)==1); EVP_CIPHER_CTX_set_padding(ctx,0);
  assert(EVP_EncryptUpdate(ctx,ct,&a,pt,sizeof pt)==1); assert(EVP_EncryptFinal_ex(ctx,ct+a,&b)==1); assert(a+b==64);
  EVP_CIPHER_CTX_free(ctx); memcpy(body,salt,16); memcpy(body+16,ct,64); return 80;
}


typedef struct {
  uint8_t body[80];
  uint8_t hash[32];
  int mem_calls;
  int hash_calls;
  uint32_t valid_base;
} FakeFactory;

static bool fake_mem(void *user, uint32_t address, uint32_t len, uint8_t *out) {
  FakeFactory *f=user; f->mem_calls++;
  if (address==f->valid_base+3u && len==5u) {
    out[0]=0xee; out[1]=80; out[2]=0; out[3]=0; out[4]=0; return true;
  }
  if (address==f->valid_base+8u && len==80u) {
    memcpy(out,f->body,80); out[0]^=0x39; return true;
  }
  return false;
}
static bool fake_hash(void *user, uint8_t out[32]) {
  FakeFactory *f=user; f->hash_calls++; memcpy(out,f->hash,32); return true;
}

int main(void) {
  uint8_t pmk[48],got[48],body[80],hash[32];
  for(size_t i=0;i<48;i++) pmk[i]=(uint8_t)(0x20+i);
  size_t n=make_body(body,pmk);
  assert(gxfp_factory_pmk_decrypt(body,n,got));
  assert(memcmp(got,pmk,48)==0);

  {
    uint8_t damaged[80], recovered = 0;
    memcpy(damaged, body, n);
    damaged[0] ^= 0x55;
    assert(gxfp_factory_pmk_recover_first_byte(damaged, n, &recovered, got));
    assert(recovered == body[0]);
    assert(memcmp(got, pmk, 48) == 0);
  }

  assert(gxfp_factory_body_sha256(body,n,hash));
  {
    uint8_t damaged[80], verified[48], bad_hash[32];
    memcpy(damaged, body, n); damaged[0] ^= 0xa7;
    assert(gxfp_factory_pmk_recover_verified(damaged, n, hash, verified));
    assert(memcmp(verified, pmk, sizeof verified) == 0);
    memcpy(bad_hash, hash, sizeof bad_hash); bad_hash[7] ^= 1;
    assert(!gxfp_factory_pmk_recover_verified(damaged, n, bad_hash, verified));
  }
  static const uint8_t abc[]={'a','b','c'}; uint8_t abc_hash[32];
  assert(gxfp_factory_body_sha256(abc,sizeof abc,abc_hash));
  static const uint8_t want_abc[32]={
    0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,
    0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad};
  assert(memcmp(abc_hash,want_abc,32)==0);
  {
    FakeFactory f={0}; uint8_t loaded[48];
    memcpy(f.body, body, n);
    f.valid_base=0x0800a000u;
    assert(gxfp_factory_body_sha256(f.body,n,f.hash));
    assert(gxfp_factory_load_pmk(fake_mem,fake_hash,&f,loaded));
    assert(memcmp(loaded,pmk,48)==0);
    assert(f.mem_calls==4 && f.hash_calls==1);
  }
  body[16]^=1;
  assert(!gxfp_factory_pmk_decrypt(body,n,got));
  puts("test_factory_pmk: OK");
  return 0;
}
