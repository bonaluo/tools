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
  return obj;
}