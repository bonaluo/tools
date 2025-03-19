// https://mihomo.party/docs/guide/override/javascript

// 返回config中proxy名称符合规则rule的
function findProxy(config, rule) {
    let res = [];
    config.proxies.forEach(proxy => {
      if (proxy.name.match(rule)) res.push(proxy.name);
    });
    if (res.length === 0) res.push('DIRECT');
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
    let appendProxyGroups = [
      { name: '直连', rule: /DIRECT/ },
      { name: '全部', rule: /.*/ },
      { name: '香港', rule: /[HK|香港]/ },
      { name: '台湾', rule: /[TW|台湾]/ },
      { name: '非日本', rule: /^(?!.*[JP|日本]).*$/ }
    ]
    appendProxyGroups.forEach(({ name, rule }) => {
      obj['proxy-groups'].push({
        name, type: 'url-test', proxies: findProxy(obj, rule),
        url: 'http://www.gstatic.com/generate_204', interval: 600
      });
    })
    return obj;
  }