// Independent C++ assertions over the derived graph, using audited strict JCS.
#define main existing_jcs_probe_main
#include "jcs_probe.cpp"
#undef main
#include <fstream>
#include <regex>
#include <sstream>

using V = jcs::Value;
const V* member(const V& v, const std::string& key) {
  for (const auto& row : v.object) if (row.first == key) return &row.second;
  return nullptr;
}
const V& get(const V& v, const std::string& key) {auto p=member(v,key);if(!p)throw std::invalid_argument("Missing probe member");return *p;}
bool type(const std::string& name, const V& value) {
  if(name=="null")return value.kind==V::Null;
  if(name=="boolean")return value.kind==V::Boolean;
  if(name=="object")return value.kind==V::Object;
  if(name=="array")return value.kind==V::Array;
  if(name=="string")return value.kind==V::String;
  if(name=="number")return value.kind==V::Number && std::isfinite(value.number);
  if(name=="integer")return value.kind==V::Number && std::isfinite(value.number) && value.number==std::floor(value.number);
  throw std::invalid_argument("Unsupported type");
}
bool same(const V& a,const V& b) {return jcs::encode(a)==jcs::encode(b);}
bool pattern(const std::string& expression,const std::string& value) {
  auto e=jcs::utf16(expression),v=jcs::utf16(value);
  if(expression==".*\\S.*") {
    for(unsigned c:v) if(!((c>=9&&c<=13)||(c>=28&&c<=32)||c==0x85||c==0xa0||c==0x1680||
      (c>=0x2000&&c<=0x200a)||c==0x2028||c==0x2029||c==0x202f||c==0x205f||c==0x3000))return true;
    return false;
  }
  return std::regex_search(std::wstring(v.begin(),v.end()),std::wregex(std::wstring(e.begin(),e.end()),std::regex::ECMAScript));
}
bool date(const std::string& s) {
  if(!std::regex_match(s,std::regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")))return false;
  int y=std::stoi(s.substr(0,4)),m=std::stoi(s.substr(5,2)),d=std::stoi(s.substr(8,2));
  const int days[]={0,31,28,31,30,31,30,31,31,30,31,30,31};
  return y>=1&&m>=1&&m<=12&&d>=1&&d<=days[m]+(m==2&&y%4==0&&(y%100!=0||y%400==0));
}
bool format(const std::string& name,const std::string& s) {
  if(name=="date")return date(s);
  if(name=="email")return s.find('@')!=std::string::npos;
  if(name=="uuid")return std::regex_match(s,std::regex("[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"));
  if(name=="date-time") {
    std::smatch match;
    if(!std::regex_match(s,match,std::regex("([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})")))return false;
    if(!date(match[1])||std::stoi(match[2])>23||std::stoi(match[3])>59||std::stoi(match[4])>59)return false;
    auto offset=match[6].str();return offset.size()==1||(std::stoi(offset.substr(1,2))<=23&&std::stoi(offset.substr(4,2))<=59);
  }
  throw std::invalid_argument("Unsupported format");
}
struct Assertions {
  const std::vector<V>& nodes;
  bool valid(std::size_t index,const V& value,int depth=0) const {
    if(depth>256||index>=nodes.size())return false;
    const auto& rule=nodes[index];
    auto child=[&](const V& n,const V& v){return valid(static_cast<std::size_t>(n.number),v,depth+1);};
    auto minimum=[&](const std::string& name,double v){auto p=member(rule,name);return p&&v<p->number;};
    auto maximum=[&](const std::string& name,double v){auto p=member(rule,name);return p&&v>p->number;};
    if(auto p=member(rule,"boolean"))return p->boolean;
    if(auto p=member(rule,"ref"))if(!child(*p,value))return false;
    if(auto p=member(rule,"type")) {
      if(p->kind==V::String) {if(!type(p->string,value))return false;}
      else if(std::none_of(p->array.begin(),p->array.end(),[&](const V& t){return type(t.string,value);}))return false;
    }
    if(auto p=member(rule,"const"))if(!same(*p,value))return false;
    if(auto p=member(rule,"enum"))if(std::none_of(p->array.begin(),p->array.end(),[&](const V& v){return same(v,value);}))return false;
    for(const std::string name:{"allOf","anyOf","oneOf"})if(auto p=member(rule,name)) {
      std::size_t count=0;for(const auto& n:p->array)if(child(n,value))++count;
      if((name=="allOf"&&count!=p->array.size())||(name=="anyOf"&&count==0)||(name=="oneOf"&&count!=1))return false;
    }
    if(auto p=member(rule,"not"))if(child(*p,value))return false;
    if(auto p=member(rule,"if"))if(auto branch=member(rule,child(*p,value)?"then":"else"))if(!child(*branch,value))return false;
    if(value.kind==V::Number&&(minimum("minimum",value.number)||maximum("maximum",value.number)))return false;
    if(value.kind==V::String) {
      std::size_t count=0;for(std::size_t i=0;i<value.string.size();++count)jcs::next_utf8(value.string,i);
      if(minimum("minLength",count)||maximum("maxLength",count))return false;
      if(auto p=member(rule,"pattern"))if(!pattern(p->string,value.string))return false;
      if(auto p=member(rule,"format"))if(!format(p->string,value.string))return false;
    }
    if(value.kind==V::Array) {
      if(minimum("minItems",value.array.size())||maximum("maxItems",value.array.size()))return false;
      if(auto p=member(rule,"uniqueItems"))if(p->boolean) {std::set<std::string> unique;for(const auto& v:value.array)unique.insert(jcs::encode(v));if(unique.size()!=value.array.size())return false;}
      if(auto p=member(rule,"items"))for(const auto& v:value.array)if(!child(*p,v))return false;
    }
    if(value.kind==V::Object) {
      if(minimum("minProperties",value.object.size())||maximum("maxProperties",value.object.size()))return false;
      if(auto p=member(rule,"required"))for(const auto& key:p->array)if(!member(value,key.string))return false;
      const auto* properties=member(rule,"properties");const auto* patterns=member(rule,"patternProperties");
      for(const auto& row:value.object) {
        const auto* field=properties?member(*properties,row.first):nullptr;bool matched=field!=nullptr;
        if(field&&!child(*field,row.second))return false;
        if(patterns)for(const auto& p:patterns->object)if(pattern(p.first,row.first)){matched=true;if(!child(p.second,row.second))return false;}
        if(!matched)if(auto p=member(rule,"additionalProperties"))if(!child(*p,row.second))return false;
        if(auto p=member(rule,"propertyNames")){V key;key.kind=V::String;key.string=row.first;if(!child(*p,key))return false;}
      }
      if(auto p=member(rule,"dependentRequired"))for(const auto& row:p->object)if(member(value,row.first))for(const auto& key:row.second.array)if(!member(value,key.string))return false;
    }
    return true;
  }
};
int main(int argc,char** argv) {
  if(argc!=2||!std::setlocale(LC_NUMERIC,"C")||std::fesetround(FE_TONEAREST)!=0)return 2;
  std::ifstream input(argv[1],std::ios::binary);std::ostringstream bytes;bytes<<input.rdbuf();const std::string raw=bytes.str();
  auto bundle=jcs::Parser(raw).parse();Assertions assertions{get(bundle,"nodes").array};
  for(const auto& item:get(bundle,"cases").array) {
    try {
      auto value=jcs::Parser(get(item,"input_json").string).parse();auto root=static_cast<std::size_t>(get(item,"root").number);
      if(!assertions.valid(root,value)){std::cout<<"REJECT\n";continue;}
      auto canonical=jcs::encode(value);auto again=jcs::Parser(canonical).parse();
      if(!assertions.valid(root,again)||canonical!=jcs::encode(again))throw std::invalid_argument("Round trip changed");
      std::cout<<"VALID\t"<<jcs::hex(canonical)<<'\n';
    }catch(const std::exception&){std::cout<<"REJECT\n";}
  }
}
