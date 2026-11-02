// Tạo trang web tĩnh cho GitHub Pages (thư mục docs/): trang chủ và trang
// Chính sách quyền riêng tư. Chữ của chính sách lấy từ docs/privacy/vi.md và en.md,
// đúng các file app đóng gói, nên app và web không thể lệch nhau.
//
// Chạy lại sau mỗi lần sửa chữ:  dart run tool/build_privacy_page.dart
// test/privacy_test.dart báo lỗi nếu các file .html trong docs/ cũ hơn bản chữ.

import 'dart:convert';

import 'package:sochitieu/utils/policy_text.dart';

const _contactEmail = 'sanchykids@gmail.com';

/// Năm của ngày hiệu lực (dòng "Có hiệu lực từ 02/11/2026" / "Effective 2 November 2026"),
/// dùng cho dòng "© năm Sổ chi tiêu".
String policyYear(PolicyDoc doc) {
  final intro = doc.intro.expand((b) => b.items).expand((i) => i).map((p) => p.text).join();
  final year = RegExp(r'\b(\d{4})\b').firstMatch(intro)?.group(1);
  if (year == null) throw FormatException('Không thấy năm hiệu lực trong dòng đầu: "$intro"');
  return year;
}

const _esc = HtmlEscape(HtmlEscapeMode.attribute);

String _escape(String s) => _esc.convert(s);

/// Bọc các địa chỉ web và email trong chữ thành liên kết (chỉ trên web; trong app chúng là chữ thường).
String _linkify(String text) {
  final link = RegExp(r'(https?://[^\s<]*[^\s<.,;:!?)])|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})');
  final out = StringBuffer();
  var last = 0;
  for (final m in link.allMatches(text)) {
    out.write(_escape(text.substring(last, m.start)));
    final value = m.group(0)!;
    final href = m.group(1) != null ? value : 'mailto:$value';
    out.write('<a href="${_escape(href)}">${_escape(value)}</a>');
    last = m.end;
  }
  out.write(_escape(text.substring(last)));
  return out.toString();
}

String _inline(List<PolicyInline> parts) => parts.map((p) {
      final html = _linkify(p.text);
      return switch (p.style) {
        InlineStyle.bold => '<strong>$html</strong>',
        InlineStyle.code => '<code>$html</code>',
        InlineStyle.plain => html,
      };
    }).join();

String _block(PolicyBlock b, String indent) {
  if (!b.isList) return '$indent<p>${_inline(b.items.single)}</p>\n';
  final items = b.items.map((i) => '$indent  <li>${_inline(i)}</li>\n').join();
  return '$indent<ul>\n$items$indent</ul>\n';
}

String _css(String root) => '''
@font-face{font-family:"Be Vietnam Pro";font-weight:400;font-display:swap;src:url("${root}fonts/BeVietnamPro-Regular.ttf") format("truetype")}
@font-face{font-family:"Be Vietnam Pro";font-weight:600;font-display:swap;src:url("${root}fonts/BeVietnamPro-SemiBold.ttf") format("truetype")}
@font-face{font-family:"Be Vietnam Pro";font-weight:700;font-display:swap;src:url("${root}fonts/BeVietnamPro-Bold.ttf") format("truetype")}
:root{--accent:#0F766E;--accent-soft:rgba(15,118,110,.12);--ink:#16181D;--text:#2A2F38;--muted:#5B6270;--line:#E4E7EC;--card:#F8F9FA;--track:#F1F3F5;color-scheme:light}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:#FFFFFF;color:var(--ink);font-family:"Be Vietnam Pro",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:15px;line-height:1.6}
a{color:var(--accent);text-decoration:underline;text-underline-offset:2px;overflow-wrap:anywhere}
.top{position:sticky;top:0;z-index:1;height:64px;padding:0 12px 0 16px;display:flex;align-items:center;justify-content:space-between;gap:12px;border-bottom:1px solid var(--line);background:#FFFFFF}
.brand{display:flex;align-items:center;gap:10px;min-height:44px;color:var(--ink);text-decoration:none;font-size:16px;font-weight:700}
.brand img{width:32px;height:32px;border-radius:10px;display:block}
.switch{display:none;gap:2px;padding:3px;border-radius:12px;background:var(--track)}
html.js .switch{display:flex}
.switch button{min-width:48px;height:40px;padding:0 10px;border:0;border-radius:9px;background:transparent;color:var(--muted);font:inherit;font-size:14px;font-weight:600;cursor:pointer}
.switch button[aria-pressed="true"]{background:#FFFFFF;color:var(--ink);box-shadow:0 1px 3px rgba(16,24,40,.12)}
.switch button:focus-visible,a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
main{max-width:720px;margin:0 auto;padding:24px 20px 40px}
html.js[data-lang="vi"] [data-l="en"],html.js[data-lang="en"] [data-l="vi"]{display:none}
html:not(.js) [data-l]+[data-l]{margin-top:40px;padding-top:32px;border-top:1px solid var(--line)}
footer{margin-top:8px;padding-top:20px;border-top:1px solid var(--line);display:flex;flex-direction:column;gap:8px;font-size:14px;color:var(--muted)}
footer .home{min-height:44px;display:flex;align-items:center;font-weight:600;text-decoration:none}
''';

String _head({required String root, required String title, required String description, required String extraCss}) => '''
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(title)}</title>
<meta name="description" content="${_escape(description)}">
<link rel="icon" type="image/png" href="${root}logo.png">
<style>
${_css(root)}$extraCss</style>
<script>
(function(){var d=document.documentElement,h=location.hash.slice(1),l=h==="vi"||h==="en"?h:((navigator.language||"").toLowerCase().indexOf("vi")===0?"vi":"en");d.className+=" js";d.setAttribute("data-lang",l);d.lang=l})();
</script>
</head>
''';

String _switch() => '''
  <div class="switch" role="group" aria-label="Ngôn ngữ / Language">
    <button type="button" data-set="vi" aria-pressed="false" lang="vi" title="Tiếng Việt">VI</button>
    <button type="button" data-set="en" aria-pressed="false" lang="en" title="English">EN</button>
  </div>
''';

/// Đổi ngôn ngữ không tải lại trang: cập nhật `<html lang>`, tiêu đề tab, nút đang chọn và `#vi` / `#en`.
String _script(Map<String, String> titles) => '''
<script>
(function(){
  var d=document.documentElement,T={vi:${jsonEncode(titles['vi'])},en:${jsonEncode(titles['en'])}};
  function set(l,fromUser){
    d.setAttribute("data-lang",l);d.lang=l;document.title=T[l];
    var b=document.querySelectorAll("[data-set]");
    for(var i=0;i<b.length;i++)b[i].setAttribute("aria-pressed",String(b[i].getAttribute("data-set")===l));
    var a=document.querySelectorAll("[data-carry]");
    for(var j=0;j<a.length;j++)a[j].setAttribute("href",a[j].getAttribute("data-carry")+"#"+l);
    if(fromUser){if(location.hash!=="#"+l)history.replaceState(null,"","#"+l);window.scrollTo(0,0)}
  }
  var b=document.querySelectorAll("[data-set]");
  for(var i=0;i<b.length;i++)b[i].addEventListener("click",function(){set(this.getAttribute("data-set"),true)});
  window.addEventListener("hashchange",function(){var h=location.hash.slice(1);if(h==="vi"||h==="en")set(h,false)});
  set(d.getAttribute("data-lang"),false);
})();
</script>
''';

const _privacyCss = '''
article h1{margin:0;font-size:28px;font-weight:700;letter-spacing:-.01em;line-height:1.25}
.meta{margin:6px 0 0;font-size:13px;color:var(--muted)}
.meta strong{font-weight:600;color:inherit}
article section{margin-top:24px}
article h2{margin:0 0 10px;font-size:17px;font-weight:700;line-height:1.35}
article p{margin:10px 0 0;color:var(--text)}
article h2+p,article h2+ul{margin-top:0}
article ul{margin:10px 0 0;padding-left:20px;color:var(--text)}
article li+li{margin-top:8px}
article strong{font-weight:600;color:var(--ink)}
article code{font:inherit;font-weight:600;color:var(--ink);overflow-wrap:anywhere}
article footer{margin-top:32px}
''';

const _privacyTitles = {
  'vi': 'Chính sách quyền riêng tư · Sổ chi tiêu',
  'en': 'Privacy Policy · Sổ chi tiêu',
};

String _article(String lang, PolicyDoc doc, String year) {
  final b = StringBuffer()
    ..write('<article lang="$lang" data-l="$lang">\n')
    ..write('  <h1>${_escape(doc.title)}</h1>\n');
  for (final block in doc.intro) {
    for (final item in block.items) {
      b.write('  <p class="meta">${_inline(item)}</p>\n');
    }
  }
  for (final s in doc.sections) {
    b
      ..write('  <section>\n')
      ..write('    <h2>${_escape(s.heading)}</h2>\n');
    for (final block in s.blocks) {
      b.write(_block(block, '    '));
    }
    b.write('  </section>\n');
  }
  final home = lang == 'vi' ? '← Trang chủ' : '← Home';
  b
    ..write('  <footer>\n')
    ..write('    <a class="home" href="../#$lang">${_escape(home)}</a>\n')
    ..write('    <span>${_linkify(_contactEmail)}</span>\n')
    ..write('    <span>© $year Sổ chi tiêu</span>\n')
    ..write('  </footer>\n')
    ..write('</article>\n');
  return b.toString();
}

/// docs/privacy/index.html: cả hai bản (Tiếng Việt rồi English) nằm sẵn trong HTML,
/// JavaScript chỉ ẩn bản không chọn. Không có JavaScript thì đọc được cả hai.
String buildPrivacyPage({required PolicyDoc vi, required PolicyDoc en}) {
  final year = policyYear(vi);
  final b = StringBuffer()
    ..write(_head(
      root: '../',
      title: 'Chính sách quyền riêng tư / Privacy Policy · Sổ chi tiêu',
      description: 'Chính sách quyền riêng tư của ứng dụng Sổ chi tiêu. Privacy Policy of the Sổ chi tiêu app.',
      extraCss: _privacyCss,
    ))
    ..write('<body>\n')
    ..write('<header class="top">\n')
    ..write('  <a class="brand" href="../" data-carry="../"><img src="../logo.png" alt="" width="32" height="32"><span>Sổ chi tiêu</span></a>\n')
    ..write(_switch())
    ..write('</header>\n')
    ..write('<main>\n')
    ..write(_article('vi', vi, year))
    ..write(_article('en', en, year))
    ..write('</main>\n')
    ..write(_script(_privacyTitles))
    ..write('</body>\n</html>\n');
  return b.toString();
}

const _homeCss = '''
main{padding-top:32px}
.hero{display:flex;flex-direction:column;align-items:flex-start;gap:14px}
.hero img{width:72px;height:72px;border-radius:22px;display:block}
.hero h1{margin:0;font-size:32px;font-weight:700;letter-spacing:-.02em;line-height:1.2}
.tagline{margin:0;font-size:18px;font-weight:600;line-height:1.4}
.desc{margin:0;color:var(--text)}
.features{list-style:none;margin:28px 0 0;padding:0;display:flex;flex-direction:column;gap:12px}
.features li{display:flex;gap:14px;padding:16px;border:1px solid var(--line);border-radius:16px;background:var(--card)}
.features .icon{width:40px;height:40px;flex-shrink:0;border-radius:13px;background:var(--accent-soft);display:flex;align-items:center;justify-content:center}
.features b{display:block;font-size:15px;font-weight:600}
.features span span{display:block;font-size:14px;line-height:1.5;color:var(--muted)}
.promise{margin:28px 0 0;font-size:14px;line-height:1.5;color:var(--muted)}
.cta{margin-top:28px;height:52px;border-radius:14px;background:var(--accent);color:#FFFFFF;display:flex;align-items:center;justify-content:center;font-size:16px;font-weight:600;text-decoration:none}
.home-block footer{margin-top:28px}
''';

const _homeTitles = {
  'vi': 'Sổ chi tiêu · Sổ ghi chép chi tiêu cá nhân cho Android',
  'en': 'Sổ chi tiêu · A personal expense notebook for Android',
};

/// Chữ trang chủ (theo bản thiết kế đã duyệt, màn "Trang web – trang chủ").
const _home = {
  'vi': {
    'tagline': 'Sổ ghi chép chi tiêu cá nhân cho Android.',
    'desc': 'Ghi lại từng khoản chi trong vài giây, xem tổng theo ngày, theo tháng và theo danh mục. '
        'Chạy offline, dữ liệu nằm trên điện thoại của bạn.',
    'f1': 'Ghi nhanh, xem rõ',
    'f1t': 'Tổng chi theo ngày, theo tháng và theo danh mục.',
    'f2': 'Nguồn tiền',
    'f2t': 'Tiền mặt, ngân hàng, ví điện tử, thẻ tín dụng; số dư tự tính.',
    'f3': 'Sao lưu tuỳ chọn',
    'f3t': 'Lưu bản sao vào Google Drive của chính bạn, trong thư mục riêng của app.',
    'promise': 'Không quảng cáo, không theo dõi, không có máy chủ riêng.',
    'privacy': 'Chính sách quyền riêng tư',
    'contact': 'Liên hệ:',
  },
  'en': {
    'tagline': 'A personal expense notebook for Android.',
    'desc': 'Record each expense in seconds and see totals by day, month and category. '
        'Works offline; your data stays on your phone.',
    'f1': 'Quick to record, easy to read',
    'f1t': 'Spending totals by day, by month and by category.',
    'f2': 'Money sources',
    'f2t': 'Cash, bank, e-wallet and credit card, with balances worked out for you.',
    'f3': 'Optional backup',
    'f3t': 'Save a copy to your own Google Drive, in a folder only the app can use.',
    'promise': 'No ads, no tracking, no server of its own.',
    'privacy': 'Privacy Policy',
    'contact': 'Contact:',
  },
};

const _featureIcons = [
  'M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z M4 10h16 M8 3v4 M16 3v4',
  'M4 7V6a2 2 0 0 1 2-2h11v3 M4 7h15a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z M16 13.5h.01',
  'M7 18a4 4 0 0 1-.6-7.96A6 6 0 0 1 17.7 9 4.5 4.5 0 0 1 17 18z',
];

String _homeBlock(String lang, String year) {
  final t = _home[lang]!;
  final b = StringBuffer()
    ..write('<div class="home-block" lang="$lang" data-l="$lang">\n')
    ..write('  <section class="hero">\n')
    ..write('    <img src="logo.png" alt="" width="72" height="72">\n')
    ..write('    <h1>Sổ chi tiêu</h1>\n')
    ..write('    <p class="tagline">${_escape(t['tagline']!)}</p>\n')
    ..write('    <p class="desc">${_escape(t['desc']!)}</p>\n')
    ..write('  </section>\n')
    ..write('  <ul class="features">\n');
  for (var i = 0; i < 3; i++) {
    b
      ..write('    <li><span class="icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0F766E" '
          'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
          '<path d="${_featureIcons[i]}"></path></svg></span>')
      ..write('<span><b>${_escape(t['f${i + 1}']!)}</b><span>${_escape(t['f${i + 1}t']!)}</span></span></li>\n');
  }
  b
    ..write('  </ul>\n')
    ..write('  <p class="promise">${_escape(t['promise']!)}</p>\n')
    ..write('  <a class="cta" href="privacy/#$lang">${_escape(t['privacy']!)}</a>\n')
    ..write('  <footer>\n')
    ..write('    <span>${_escape(t['contact']!)} ${_linkify(_contactEmail)}</span>\n')
    ..write('    <span>© $year Sổ chi tiêu</span>\n')
    ..write('  </footer>\n')
    ..write('</div>\n');
  return b.toString();
}

/// docs/index.html: trang chủ (URL "homepage" cho màn Branding của Google Cloud).
String buildHomePage({required String year}) {
  final b = StringBuffer()
    ..write(_head(
      root: '',
      title: 'Sổ chi tiêu · Sổ ghi chép chi tiêu cá nhân / A personal expense notebook',
      description: 'Sổ chi tiêu: sổ ghi chép chi tiêu cá nhân cho Android, chạy offline. '
          'A personal expense notebook for Android that works offline.',
      extraCss: _homeCss,
    ))
    ..write('<body>\n')
    ..write('<header class="top">\n')
    ..write('  <span class="brand"><img src="logo.png" alt="" width="32" height="32"><span>Sổ chi tiêu</span></span>\n')
    ..write(_switch())
    ..write('</header>\n')
    ..write('<main>\n')
    ..write(_homeBlock('vi', year))
    ..write(_homeBlock('en', year))
    ..write('</main>\n')
    ..write(_script(_homeTitles))
    ..write('</body>\n</html>\n');
  return b.toString();
}
