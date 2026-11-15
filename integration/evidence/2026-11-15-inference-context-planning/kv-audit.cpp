#include "model/Qwen3_6Moe.hpp"
#include <iostream>
int main(){constexpr splash::model::Qwen3_6MoeLayout model{};constexpr auto kv=model.kvLayout();std::cout<<"bytesPerPage="<<kv.bytesPerModelPage()<<" pageTokens="<<splash::kv::kPageTokens<<" attentionLayers="<<kv.attentionLayers<<" kvHeads="<<kv.kvHeads<<" headDim="<<kv.headDimension<<"\n";for(unsigned tokens:{32768u,65536u,131072u,262144u,1010000u}) {auto pages=(tokens+splash::kv::kPageTokens-1)/splash::kv::kPageTokens;std::cout<<tokens<<","<<pages*kv.bytesPerModelPage()<<"\n";}}
