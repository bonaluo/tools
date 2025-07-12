// https://mihomo.party/docs/guide/override/javascript

// 返回config中proxy名称符合规则rule的
function findProxy(config, rule, defualt) {
  let res = [];
  config.proxies.forEach(proxy => {
    if (proxy.name.match(rule)) res.push(proxy.name);
  });
  if (res.length === 0) res = defualt;
  return res;
}

function main(config) {
  const obj = config;
  // 移除策略组中的倍率节点
  obj['proxy-groups'].forEach(group => {
    group.proxies = group.proxies.filter(proxyName => !proxyName.includes('倍率'));
  })
  // 移除倍率节点
  obj.proxies = obj.proxies.filter(proxy => !proxy.name.includes('倍率'));
  // 按照名称分组
  let result = {};
  obj.proxies.forEach(item => {
    let match = item.name.match(/^(.*)-\d{2}$/);
    if (match) {
      // 移除方括号及其内容
      let key = match[1].replace(/\[.*]/g, '');
      if (!result[key]) {
        result[key] = [];
      }
      result[key].push(item.name);
    }
  });
  // 添加名称分组
  for (let key in result) {
    if (result[key].length >= 1) {
      obj['proxy-groups'].push({
        name: key, type: 'url-test', proxies: result[key],
        url: 'http://www.gstatic.com/generate_204', interval: 600
      });
    }
  }
  // 添加自定义分组
  // 注意 | 的外层使用 () 而不是 []
  let appendProxyGroups = [
    { name: '直连', rule: /DIRECT/, defualt: ['DIRECT'], type: 'select' },
    { name: '全部', rule: /.*/, type: 'url-test' },
    { name: '香港', rule: /(HK|香港)/, type: 'url-test' },
    { name: '台湾', rule: /(TW|台湾)/, type: 'url-test' },
    { name: '日本', rule: /(JP|日本)/, type: 'url-test' },
    { name: '非日本', rule: /^(?!.*(JP|日本)).*$/, type: 'url-test' }

  ]
  appendProxyGroups.forEach(({ name, rule, defualt, type }) => {
    obj['proxy-groups'].push({
      name, type: type, proxies: findProxy(obj, rule, defualt),
      url: 'http://www.gstatic.com/generate_204', interval: 600
    });

  })

  // 添加规则，对于某些脚本和规则覆写不能同时使用，优先使用脚本
  // addRules(obj);
  return obj;
}

const domainRules = [
  "DOMAIN-SUFFIX,jable.tv,非日本",
  "DOMAIN-SUFFIX,missav.ai,非日本",
  "DOMAIN-SUFFIX,pornhub.com,非日本",
  "DOMAIN-SUFFIX,hanime1.me,非日本",
  "DOMAIN-SUFFIX,anime1.me,非日本",
  "DOMAIN-SUFFIX,18commic.vip,非日本",
  "DOMAIN-SUFFIX,copilot.microsoft.com,香港",
  "DOMAIN-SUFFIX,epicgames.com,香港",
  "DOMAIN-SUFFIX,tw,台湾",
  "DOMAIN-SUFFIX,doubleclick.net,台湾",
  "DOMAIN-SUFFIX,bahamut.akamaized.net,台湾",
  "DOMAIN-SUFFIX,jp,日本",
  "DOMAIN-SUFFIX,intel.cn,直连",
  "DOMAIN-SUFFIX,intel.com,直连",
  "DOMAIN-SUFFIX,bandbbs.cn,直连",
  "DOMAIN-SUFFIX,ntdm8.com,直连",
  "DOMAIN-SUFFIX,lanzoux.com,全部",
  "DOMAIN-SUFFIX,ghcr.io,全部",
  "DOMAIN-SUFFIX,home-assistant.io,全部"
];


// 添加规则，对于某些脚本和规则覆写不能同时使用，优先使用脚本
function addRules(obj) {
  // domainRules.forEach(rule => {
  //   obj.rules.unshift(rule);
  // })
  
  // 使用展开运算符将数组元素添加到规则列表中
  obj.rules.unshift(...domainRules);
}