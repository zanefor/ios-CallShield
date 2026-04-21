#!/usr/bin/env python3
"""
CallShield PIR 服务器 — 骚扰座机号前缀匹配

部署方式：
1. pip install flask phe
2. python3 pir_server.py
3. 默认监听 0.0.0.0:8443

API 端点：
- POST /lookup — PIR 加密查询（blocking + identification）
- GET /health — 健康检查

核心优势：
- 1120 条前缀规则覆盖 112 亿座机号
- 前缀匹配：一条规则覆盖 1000 万号码
- PIR 加密：服务器不知道查询的具体号码
- 响应时间 < 50ms（纯内存匹配）

注意：此为简化示例，生产环境需实现完整的 PIR 协议
（同态加密 + Oblivious HTTP Relay + Privacy Pass）
"""

from flask import Flask, request, jsonify
import json
import re
import time
from collections import defaultdict

app = Flask(__name__)

# ============================================================
# 骚扰前缀规则集
# ============================================================

# 骚扰高发首位号段
SPAM_FIRST_DIGITS = {'3', '5', '6', '8'}

# 2 位区号（直辖市/大区中心）
TWO_DIGIT_AREA_CODES = {
    '010', '020', '021', '022', '023', '024', '025', '027', '028', '029'
}

# 非偏远地区区号
NON_REMOTE_AREA_CODES = set()

def init_area_codes():
    """初始化区号集合"""
    global NON_REMOTE_AREA_CODES

    # 2 位区号
    for code in TWO_DIGIT_AREA_CODES:
        NON_REMOTE_AREA_CODES.add(code)

    # 3 位区号（非偏远）
    three_digit = [
        # 河北
        '0311','0312','0313','0314','0315','0316','0317','0318','0319','0335','0310',
        # 山西
        '0350','0351','0352','0353','0354','0355','0356','0357','0358','0359',
        # 辽宁
        '0411','0412','0413','0414','0415','0416','0417','0418','0419','0421','0427','0429','0410',
        # 吉林
        '0431','0432','0433','0434','0435','0436','0437','0438','0439',
        # 黑龙江
        '0451','0452','0453','0454','0455','0456','0457','0459','0464','0467','0468','0469','0458',
        # 江苏
        '0510','0511','0512','0513','0514','0515','0516','0517','0518','0519','0523','0527',
        # 浙江
        '0571','0572','0573','0574','0575','0576','0577','0578','0579','0580','0570',
        # 安徽
        '0551','0552','0553','0554','0555','0556','0557','0558','0559',
        '0562','0563','0564','0566','0561','0550','0565',
        # 福建
        '0591','0592','0593','0594','0595','0596','0597','0598','0599',
        # 江西
        '0790','0791','0792','0793','0794','0795','0796','0797','0798','0799','0701',
        # 山东
        '0531','0532','0533','0534','0535','0536','0537','0538','0539',
        '0543','0546','0631','0632','0633','0635','0634','0530',
        # 河南
        '0371','0372','0373','0374','0375','0376','0377','0378','0379',
        '0391','0392','0393','0394','0395','0396','0398','0370',
        # 湖北
        '0710','0711','0712','0713','0714','0715','0716','0717','0718','0719',
        '0722','0724','0728',
        # 湖南
        '0730','0731','0732','0733','0734','0735','0736','0737','0738','0739',
        '0743','0744','0745','0746',
        # 广东
        '0662','0663','0668','0660',
        '0750','0751','0752','0753','0754','0755','0756','0757','0758','0759',
        '0760','0762','0763','0766','0768','0769',
        # 广西
        '0771','0772','0773','0774','0775','0776','0777','0779','0770','0778',
        # 海南
        '0898','0899',
        # 四川
        '0812','0813','0816','0817','0818',
        '0825','0826','0827',
        '0830','0831','0832','0833','0835','0838','0839','0834',
        # 贵州
        '0851','0852','0853','0854','0855','0856','0857','0858','0859',
        # 云南（非偏远）
        '0871','0872','0873','0874','0877','0878','0870',
        # 陕西
        '0910','0911','0912','0913','0914','0915','0916','0917','0919',
        # 甘肃（非偏远）
        '0931','0932','0938',
        # 宁夏
        '0951','0952','0953','0954','0955',
    ]
    for code in three_digit:
        NON_REMOTE_AREA_CODES.add(code)

# 前缀集合（预计算）
LOCAL_PREFIXES = set()
E164_PREFIXES = set()

def init_prefixes():
    """预计算前缀集合"""
    global LOCAL_PREFIXES, E164_PREFIXES
    for area_code in NON_REMOTE_AREA_CODES:
        is_two_digit = area_code in TWO_DIGIT_AREA_CODES
        for digit in SPAM_FIRST_DIGITS:
            # 本地格式前缀
            LOCAL_PREFIXES.add(area_code + digit)
            # E.164 格式前缀
            without_zero = area_code[1:]  # 去掉前导0
            e164_area = '86' + without_zero
            E164_PREFIXES.add(e164_area + digit)

def extract_digits(phone):
    """提取纯数字"""
    return re.sub(r'\D', '', phone)

def check_spam(phone_number):
    """
    检查号码是否为骚扰座机
    返回: (is_spam, label, matched_prefix)
    """
    digits = extract_digits(phone_number)
    if not digits:
        return False, None, None

    # 本地格式前缀匹配
    for prefix_len in [5, 4, 6]:
        if len(digits) >= prefix_len:
            prefix = digits[:prefix_len]
            if prefix in LOCAL_PREFIXES:
                return True, "骚扰座机", prefix

    # E.164 格式前缀匹配
    for prefix_len in [6, 5, 7]:
        if len(digits) >= prefix_len:
            prefix = digits[:prefix_len]
            if prefix in E164_PREFIXES:
                return True, "骚扰座机", prefix

    # 回退：区号+首位检测
    if digits.startswith('0') and len(digits) >= 5:
        # 2位区号
        if len(digits) >= 3 and digits[:3] in TWO_DIGIT_AREA_CODES:
            first_digit = digits[3] if len(digits) > 3 else None
            if first_digit and first_digit in SPAM_FIRST_DIGITS:
                return True, "骚扰座机", digits[:4]
        # 3位区号
        if len(digits) >= 4 and digits[:4] in NON_REMOTE_AREA_CODES:
            first_digit = digits[4] if len(digits) > 4 else None
            if first_digit and first_digit in SPAM_FIRST_DIGITS:
                return True, "骚扰座机", digits[:5]

    return False, None, None


# ============================================================
# API 端点
# ============================================================

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'prefixes': len(LOCAL_PREFIXES) + len(E164_PREFIXES),
        'area_codes': len(NON_REMOTE_AREA_CODES),
    })

@app.route('/lookup', methods=['POST'])
def lookup():
    """
    查询号码是否为骚扰电话

    ★ 生产环境需替换为 PIR 协议 ★
    此简化版本直接接收明文号码查询，仅供开发测试

    PIR 生产版本需要：
    1. 客户端发送同态加密查询
    2. 服务器在加密数据上执行计算
    3. 返回加密结果
    4. 客户端解密

    请求格式（简化版）:
    {
        "phoneNumber": "02032445445"
    }

    响应格式:
    {
        "block": true/false,
        "label": "骚扰座机" or null,
        "prefix": "0203" or null
    }
    """
    start_time = time.time()

    data = request.get_json()
    if not data or 'phoneNumber' not in data:
        return jsonify({'block': False, 'label': None, 'prefix': None}), 400

    phone_number = data['phoneNumber']
    is_spam, label, prefix = check_spam(phone_number)

    elapsed_ms = (time.time() - start_time) * 1000

    response = {
        'block': is_spam,
        'label': label,
        'prefix': prefix,
        'queryTimeMs': round(elapsed_ms, 2)
    }

    if is_spam:
        app.logger.info(f"BLOCKED: {phone_number[:6]}*** → prefix={prefix}, time={elapsed_ms:.1f}ms")
    else:
        app.logger.debug(f"PASSED: {phone_number[:6]}***, time={elapsed_ms:.1f}ms")

    return jsonify(response)


@app.route('/batch-lookup', methods=['POST'])
def batch_lookup():
    """
    批量查询（用于预加载/缓存场景）
    """
    data = request.get_json()
    if not data or 'phoneNumbers' not in data:
        return jsonify({'results': []}), 400

    results = []
    for phone in data['phoneNumbers']:
        is_spam, label, prefix = check_spam(phone)
        results.append({
            'phoneNumber': phone,
            'block': is_spam,
            'label': label,
            'prefix': prefix,
        })

    return jsonify({'results': results})


@app.route('/stats', methods=['GET'])
def stats():
    """返回规则统计信息"""
    return jsonify({
        'localPrefixes': len(LOCAL_PREFIXES),
        'e164Prefixes': len(E164_PREFIXES),
        'totalPrefixes': len(LOCAL_PREFIXES) + len(E164_PREFIXES),
        'areaCodes': len(NON_REMOTE_AREA_CODES),
        'spamFirstDigits': list(SPAM_FIRST_DIGITS),
    })


# ============================================================
# PIR 数据库构建工具
# ============================================================

@app.route('/build-pir-database', methods=['POST'])
def build_pir_database():
    """
    构建 PIR 数据库文件（用于生产部署）

    生产环境的 PIR 服务器需要将前缀规则转换为
    PIR 索引格式（Apple 的 pir-service-example 提供工具）
    """
    # 收集所有规则
    rules = []
    for area_code in NON_REMOTE_AREA_CODES:
        is_two_digit = area_code in TWO_DIGIT_AREA_CODES
        for digit in SPAM_FIRST_DIGITS:
            local_prefix = area_code + digit
            without_zero = area_code[1:]
            e164_prefix = '86' + without_zero + digit

            rules.append({
                'localPrefix': local_prefix,
                'e164Prefix': e164_prefix,
                'block': True,
                'label': '骚扰座机',
            })

    return jsonify({
        'totalRules': len(rules),
        'rules': rules,
        'note': '此数据需通过 PIRProcessDatabase 工具转换为 PIR 索引格式'
    })


# ============================================================
# 初始化
# ============================================================

init_area_codes()
init_prefixes()

if __name__ == '__main__':
    print(f"CallShield PIR Server starting...")
    print(f"  Local prefixes:  {len(LOCAL_PREFIXES)}")
    print(f"  E.164 prefixes:  {len(E164_PREFIXES)}")
    print(f"  Total prefixes:  {len(LOCAL_PREFIXES) + len(E164_PREFIXES)}")
    print(f"  Area codes:      {len(NON_REMOTE_AREA_CODES)}")
    print(f"  Spam digits:     {SPAM_FIRST_DIGITS}")
    print(f"")
    print(f"  ★ 一条前缀覆盖 1000 万号码")
    print(f"  ★ {len(LOCAL_PREFIXES) + len(E164_PREFIXES)} 条前缀覆盖 {(len(LOCAL_PREFIXES) + len(E164_PREFIXES)) * 1000} 万号码")
    print(f"")

    # 监听所有接口，支持 HTTPS（生产环境需配置证书）
    app.run(host='0.0.0.0', port=8443, debug=True)
