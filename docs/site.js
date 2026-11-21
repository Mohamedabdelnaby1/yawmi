const root = document.documentElement;
const button = document.querySelector('.language');

function setLanguage(language) {
  const arabic = language === 'ar';
  root.lang = language;
  root.dir = arabic ? 'rtl' : 'ltr';
  document.title = arabic ? 'يومي · دفتر صحتك' : 'Yawmi · Your health journal';
  button.setAttribute('aria-label', arabic ? 'Switch to English' : 'التبديل إلى العربية');
}

setLanguage(new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'ar');
button.addEventListener('click', () => {
  const language = root.lang === 'ar' ? 'en' : 'ar';
  const url = new URL(location.href);
  url.searchParams.set('lang', language);
  history.replaceState(null, '', url);
  setLanguage(language);
});
