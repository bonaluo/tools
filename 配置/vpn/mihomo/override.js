// https://mihomo.party/docs/guide/override/javascript

// 通过正则找到符合的代理节点
function findProxy(config, pattern, defualt) {
  const res = config.proxies.filter(p => pattern.test(p.name)).map(p => p.name);
  return res.length ? res : defualt;
}

// 移除多倍率
function removeMultiPrice(config) {
  // 移除策略组中的倍率节点
  config['proxy-groups'].forEach(group => {
    group.proxies = group.proxies.filter(pn => !pn.includes('倍率'));
  })
  // 移除倍率节点
  config.proxies = config.proxies.filter(proxy => !proxy.name.includes('倍率'));
}

function addGroupByName(config) {
  // 按照名称分组
  let result = {};
  config.proxies.forEach(item => {
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
      config['proxy-groups'].push({
        name: key, type: 'url-test', proxies: result[key]
      });
    }
  }
}

function addCustomGroup(config) {
  // 添加自定义分组
  // 注意 | 的外层使用 () 而不是 []
  let appendProxyGroups = [
    { name: '直连', type: 'select', pattern: /DIRECT/i, defualt: ['DIRECT'] },
    { name: '香港', type: 'url-test', pattern: /(HK|香港)/i, defualt: ['DIRECT'] },
    { name: '台湾', type: 'url-test', pattern: /(TW|台湾)/i, defualt: ['DIRECT'] },
    { name: '日本', type: 'url-test', pattern: /(JP|日本)/i, defualt: ['DIRECT'] },
    { name: '非日本', type: 'url-test', pattern: /^(?!.*(JP|日本)).*$/i, defualt: ['DIRECT'] },
    { name: '美国', type: 'url-test', pattern: /(US|美国)/i, defualt: ['DIRECT'] },
    { name: 'GPT优化', type: 'url-test', pattern: /(gpt|优化)/i, defualt: findProxy(config, /.*/, ['DIRECT']) },
    { name: '全部-速度优先', type: 'url-test', pattern: /.*/i, defualt: ['DIRECT'] },
    { name: '全部-负载均衡', type: 'load-balance', pattern: /.*/i, defualt: ['DIRECT'] },
    // 兜底规则可以选择是直连、速度优先还是负载均衡
    { name: 'MATCH-智能路由', type: 'select', proxies: ['全部-速度优先', '全部-负载均衡', 'DIRECT', '美国'] },
  ]
  appendProxyGroups.forEach(({ name, pattern, type, defualt, proxies }) => {
    const exists = config['proxy-groups'].some(item => {
      return item.name === name;
    })
    if (exists) {
      console.log(`${name}:${exists}`);
      return;
    }
    if (proxies) {
      config['proxy-groups'].push({
        name, type: type, proxies: proxies
      });
    } else {
      config['proxy-groups'].push({
        name, type: type, proxies: findProxy(config, pattern, defualt)
      });
    }
  })
}

// 删除所有默认代理组和规则
function clearDefaultGroupsAndRules(config) {
  config['proxy-groups'] = [];
  config.rules = [];
}

// 添加默认 append 规则
function addDefaultRules(config) {
  config.rules.push('GEOSITE,cn,直连');
  config.rules.push('GEOIP,cn,直连,no-resolve');// 中国 IP 直连（不解析 DNS）
}

// 兜底规则使用的代理组
function matchDirect(config, groupName) {
  config.rules.push(`MATCH,${groupName}`);
}

function main(config) {

  clearDefaultGroupsAndRules(config);  // 清空默认代理组和规则
  // removeMultiPrice(config);// 流量很多不需要移除多倍率节点
  // addGroupByName(config);// 名称分组会添加很多分组，不如自定义分组来的清晰、可靠、稳定
  addCustomGroup(config);
  addDefaultRules(config);
  matchDirect(config, 'MATCH-智能路由');// 兜底规则使用智能路由，流量仍然可以通过智能路由进行优化


  return config;
}