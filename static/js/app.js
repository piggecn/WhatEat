/* 家庭食谱 - 前端交互逻辑（Alpine.js 组件） */
window.RecipeApp = (function () {
  const TOKEN_KEY = 'recipe_token';
  const USER_KEY = 'recipe_user';
  const COOKIE_MAX_AGE = 60 * 60 * 24 * 7; // 7 天
  const REMEMBER_COOKIE_MAX_AGE = 60 * 60 * 24 * 30; // 记住我：30 天免登录

  function setCookie(name, value, maxAge) {
    document.cookie =
      name + '=' + encodeURIComponent(value) +
      '; path=/; max-age=' + maxAge + '; SameSite=Lax';
  }
  function delCookie(name) {
    document.cookie = name + '=; path=/; max-age=0';
  }

  return {
    getToken() { return localStorage.getItem(TOKEN_KEY) || ''; },
    /* token 同步写入 localStorage（供前端 fetch 带 Authorization）和 cookie（供服务端渲染页面）。
       remember 为 true 时 cookie 有效期 30 天，否则 7 天。 */
    setToken(t, remember) {
      localStorage.setItem(TOKEN_KEY, t);
      setCookie(TOKEN_KEY, t, remember ? REMEMBER_COOKIE_MAX_AGE : COOKIE_MAX_AGE);
    },
    setUser(u) { localStorage.setItem(USER_KEY, JSON.stringify(u)); },
    getUser() {
      try { return JSON.parse(localStorage.getItem(USER_KEY) || 'null'); }
      catch (e) { return null; }
    },
    clear() {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(USER_KEY);
      delCookie(TOKEN_KEY);
    },

    /* 带认证的 fetch 封装；401 自动跳登录 */
    async api(url, options = {}) {
      const opts = Object.assign({}, options, {
        headers: Object.assign(
          options.headers || {},
          { 'Authorization': 'Bearer ' + this.getToken() }
        ),
      });
      const res = await fetch(url, opts);
      if (res.status === 401) {
        this.clear();
        window.location.href = '/login';
        throw new Error('未登录');
      }
      return res;
    },
  };
})();

/* 导航栏组件：用户下拉菜单 + 登出（用户名/头像由服务端渲染） */
function navbar() {
  return {
    userOpen: false,
    logout() {
      RecipeApp.clear();
      window.location.href = '/login';
    },
  };
}

/* 全局确认弹窗（单例，通过 window.__confirm 触发） */
function confirmDialog() {
  return {
    open: false,
    title: '',
    message: '',
    _onOk: null,
    init() {
      window.__confirm = (opts) => {
        this.title = opts.title || '确认';
        this.message = opts.message || '';
        this._onOk = opts.onOk || null;
        this.open = true;
      };
    },
    confirm() {
      const cb = this._onOk;
      this._onOk = null;
      this.open = false;
      if (cb) Promise.resolve(cb()).catch(() => {});
    },
    cancel() { this._onOk = null; this.open = false; },
  };
}

/* 登录页：POST /api/auth/login，成功存 token 跳转 / */
function loginPage() {
  return {
    form: { username: '', password: '', remember_me: true },
    error: '',
    loading: false,
    async submit() {
      this.error = '';
      this.loading = true;
      try {
        const res = await fetch('/api/auth/login', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(this.form),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '登录失败');
        RecipeApp.setToken(data.token, this.form.remember_me);
        RecipeApp.setUser(data.user);
        window.location.href = '/';
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },
  };
}

/* 图标刷新：预编译 CSS 后无需防抖，立即转换（图标数量少，开销可忽略） */
window.__refreshIcons = function () {
  if (window.lucide && window.lucide.createIcons) { window.lucide.createIcons(); }
};

/* 首页：搜索 + 分类筛选 + 卡片收藏切换 + 随机推荐（初始数据服务端 Jinja 渲染） */
function indexPage(currentCategory, currentSort) {
  return {
    q: '',
    searchHist: [],
    category: currentCategory || '',
    sort: currentSort || 'added_desc',
    init() {
      try {
        this.searchHist = JSON.parse(localStorage.getItem('whateat-search-history') || '[]');
      } catch (e) { this.searchHist = []; }
    },
    pushSearchHistory(term) {
      const t = (term || '').trim();
      if (!t) return;
      this.searchHist = [t, ...this.searchHist.filter(x => x !== t)].slice(0, 8);
      try { localStorage.setItem('whateat-search-history', JSON.stringify(this.searchHist)); } catch (e) {}
    },
    clearSearchHistory() {
      this.searchHist = [];
      try { localStorage.removeItem('whateat-search-history'); } catch (e) {}
    },
    /* 随机推荐弹窗状态 */
    rand: {
      open: false,
      loading: false,
      error: '',
      recipe: null,
      onlyStock: false,
      category: '',
      meal_type: '',
      excludeRecent: false,
      confirming: false,
      toast: '',
    },
    _randToastTimer: null,
    get seasonTip() {
      const m = new Date().getMonth() + 1;
      if (m === 12 || m <= 2) return { text: '冬季时令：宜汤类·炖菜，暖身驱寒', icon: 'soup' };
      if (m <= 5) return { text: '春季时令：宜清淡时蔬，清爽开胃', icon: 'leaf' };
      if (m <= 8) return { text: '夏季时令：宜凉菜·冷面，消暑爽口', icon: 'sun' };
      return { text: '秋季时令：宜滋补炖品，润燥养人', icon: 'wind' };
    },

    /* 提交筛选：带参数刷新页面，服务端重新渲染列表 */
    applyFilter() {
      this.pushSearchHistory(this.q);
      const params = new URLSearchParams();
      if (this.category) params.set('category', this.category);
      if (this.q) params.set('q', this.q);
      if (this.sort) params.set('sort', this.sort);
      const pathname = window.location.pathname;
      window.location.href = pathname + (params.toString() ? '?' + params.toString() : '');
    },
    selectCategory(c) {
      this.category = (this.category === c) ? '' : c;
      this.applyFilter();
    },
    /* 卡片收藏切换：局部更新爱心图标，不刷新整页 */
    async toggleFavorite(id, btnEl) {
      try {
        const res = await RecipeApp.api('/api/recipes/' + id + '/favorite', { method: 'POST' });
        const data = await res.json();
        const icon = btnEl.querySelector('i');
        if (data.is_favorite) {
          btnEl.classList.remove('text-muted-foreground');
          btnEl.classList.add('text-red-500');
          icon.classList.add('fill-current');
        } else {
          btnEl.classList.add('text-muted-foreground');
          btnEl.classList.remove('text-red-500');
          icon.classList.remove('fill-current');
        }
      } catch (e) { /* 忽略 */ }
    },

    /* ===== 随机推荐 ===== */
    openRandom() {
      this.rand.open = true;
      this.rand.error = '';
      this.rand.recipe = {};
      this.fetchRandom();
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    closeRandom() {
      this.rand.open = false;
    },
    async fetchRandom() {
      this.rand.loading = true;
      this.rand.error = '';
      this.rand.recipe = {};
      try {
        const params = new URLSearchParams();
        if (this.rand.category) params.set('category', this.rand.category);
        if (this.rand.meal_type) params.set('meal_type', this.rand.meal_type);
        if (this.rand.excludeRecent) params.set('exclude_recent_days', 3);
        if (this.rand.onlyStock) params.set('only_in_stock', 'true');
        const res = await RecipeApp.api('/api/recipes/random?' + params.toString());
        if (res.status === 404) {
          this.rand.error = '没有符合条件的食谱，调整筛选再试试';
        } else if (!res.ok) {
          const d = await res.json().catch(() => ({}));
          this.rand.error = d.detail || '获取失败';
        } else {
          this.rand.recipe = await res.json();
        }
      } catch (e) {
        this.rand.error = '网络异常，请稍后再试';
      } finally {
        this.rand.loading = false;
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
      }
    },
    async confirmRandom() {
      if (!this.rand.recipe || this.rand.confirming) return;
      this.rand.confirming = true;
      try {
        const today = new Date().toISOString().slice(0, 10);
        const res = await RecipeApp.api('/api/meals', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            recipe_id: this.rand.recipe.id,
            meal_type: 'dinner',
            date: today,
          }),
        });
        if (!res.ok) {
          const d = await res.json().catch(() => ({}));
          throw new Error(d.detail || '记录失败');
        }
        this.rand.toast = '已加入今天菜单';
        this.closeRandom();
        this._showRandToast();
        /* 局部刷新今日菜单条：直接整页刷新最简单可靠 */
        setTimeout(() => window.location.reload(), 800);
      } catch (e) {
        this.rand.toast = e.message;
        this._showRandToast();
      } finally {
        this.rand.confirming = false;
      }
    },
    resetRandFilter() {
      this.rand.category = '';
      this.rand.meal_type = '';
      this.rand.excludeRecent = false;
      this.fetchRandom();
    },
    _showRandToast() {
      if (this._randToastTimer) clearTimeout(this._randToastTimer);
      this._randToastTimer = setTimeout(() => { this.rand.toast = ''; }, 2500);
    },
  };
}

/* 烹饪模式：全屏大字步骤 + 计时器 */
function cookMode(steps) {
  return {
    open: false,
    steps: steps || [],
    idx: 0,
    seconds: 0,
    timerId: null,
    get current() { return this.steps[this.idx] || null; },
    speaking: false,
    get timeText() {
      const m = String(Math.floor(this.seconds / 60)).padStart(2, '0');
      const sec = String(this.seconds % 60).padStart(2, '0');
      return m + ':' + sec;
    },
    start() {
      this.open = true;
      this.idx = 0;
      this.stopTimer();
      this.seconds = 0;
      this.timerId = setInterval(() => { this.seconds += 1; }, 1000);
    },
    stopTimer() { if (this.timerId) { clearInterval(this.timerId); this.timerId = null; } },
    next() {
      this.speakCurrent();
      if (this.idx < this.steps.length - 1) this.idx += 1;
    },
    prev() { if (this.idx > 0) this.idx -= 1; },
    speakCurrent() {
      if (!window.speechSynthesis) return;
      window.speechSynthesis.cancel();
      const text = this.current;
      if (!text) return;
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'zh-CN';
      u.rate = 0.95;
      u.onstart = () => { this.speaking = true; };
      u.onend = () => { this.speaking = false; };
      u.onerror = () => { this.speaking = false; };
      window.speechSynthesis.speak(u);
    },
    stopSpeak() { if (window.speechSynthesis) window.speechSynthesis.cancel(); this.speaking = false; },
    exit() { this.stopTimer(); this.stopSpeak(); this.open = false; },
  };
}

/* 详情页：收藏切换 + 删除 + 今天做这个（用餐记录） */
function detailPage(recipeId, initialFav) {
  return {
    recipeId: recipeId,
    isFav: !!initialFav,
    /* 用餐记录相关状态 */
    mealPickerOpen: false,
    mealRecorded: false,
    mealRecording: false,
    mealToast: '',
    todayDate: new Date().toISOString().slice(0, 10),
    _mealToastTimer: null,

    async toggleFavorite() {
      try {
        const res = await RecipeApp.api('/api/recipes/' + this.recipeId + '/favorite', { method: 'POST' });
        const data = await res.json();
        this.isFav = data.is_favorite;
      } catch (e) { /* 忽略 */ }
    },
    askDelete() {
      const id = this.recipeId;
      window.__confirm({
        title: '删除食谱',
        message: '确定删除这道食谱吗？删除后无法恢复。',
        onOk: async () => {
          try {
            await RecipeApp.api('/api/recipes/' + id, { method: 'DELETE' });
            window.location.href = '/';
          } catch (e) { /* 忽略 */ }
        },
      });
    },

    /* ===== 复制 / 分享（导出文本） ===== */
    async _fetchRecipe() {
      const res = await RecipeApp.api('/api/recipes/' + this.recipeId);
      if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        throw new Error(d.detail || '获取食谱失败');
      }
      return res.json();
    },
    _buildShareText(r) {
      const lines = [];
      lines.push('【' + (r.title || '') + '】');
      if (r.description) lines.push(r.description);
      const meta = [];
      if (r.category) meta.push('分类：' + r.category);
      if (r.servings != null) meta.push('人数：' + r.servings + ' 人份');
      if (r.prep_time != null) meta.push('准备：' + r.prep_time + ' 分钟');
      if (r.cook_time != null) meta.push('烹饪：' + r.cook_time + ' 分钟');
      if (r.author_display_name || r.author) meta.push('作者：' + (r.author_display_name || r.author));
      if (meta.length) lines.push(meta.join(' | '));
      lines.push('');
      lines.push('食材清单');
      (r.ingredients || []).forEach((ing, i) => {
        const qty = [];
        if (ing.amount != null && ing.amount !== '') qty.push(ing.amount);
        if (ing.unit) qty.push(ing.unit);
        lines.push((i + 1) + '. ' + ing.name + (qty.length ? ' ' + qty.join(' ') : ''));
      });
      lines.push('');
      lines.push('烹饪步骤');
      (r.steps || []).forEach((s, i) => {
        lines.push((i + 1) + '. ' + s.description);
      });
      return lines.join('\n');
    },
    async _copyText(text) {
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text);
          return true;
        }
        throw new Error('no-clipboard-api');
      } catch (e) {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        let ok = false;
        try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
        document.body.removeChild(ta);
        return ok;
      }
    },
    async copyRecipe() {
      try {
        const r = await this._fetchRecipe();
        const ok = await this._copyText(this._buildShareText(r));
        this.mealToast = ok ? '菜谱已复制，去分享吧' : '复制失败，请手动长按复制';
        this._showMealToast();
      } catch (e) {
        this.mealToast = e.message;
        this._showMealToast();
      }
    },
    async shareRecipe() {
      try {
        const r = await this._fetchRecipe();
        const text = this._buildShareText(r);
        if (navigator.share) {
          await navigator.share({ title: r.title || '菜谱', text: text });
        } else {
          const ok = await this._copyText(text);
          this.mealToast = ok ? '已复制，可在其他应用粘贴分享' : '复制失败';
          this._showMealToast();
        }
      } catch (e) {
        if (!(e && e.name === 'AbortError')) {
          this.mealToast = e.message;
          this._showMealToast();
        }
      }
    },

    /* ===== 今天做这个 ===== */
    openMealPicker() {
      this.mealPickerOpen = true;
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    closeMealPicker() {
      this.mealPickerOpen = false;
    },
    async recordMeal(mealType) {
      if (this.mealRecording) return;
      this.mealRecording = true;
      try {
        const res = await RecipeApp.api('/api/meals', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            recipe_id: this.recipeId,
            meal_type: mealType,
            date: this.todayDate,
          }),
        });
        if (!res.ok) {
          const d = await res.json().catch(() => ({}));
          throw new Error(d.detail || '记录失败');
        }
        this.mealRecorded = true;
        this.mealToast = '已记录到今天' + (mealType === 'breakfast' ? '早餐' : mealType === 'lunch' ? '午餐' : '晚餐');
        this.closeMealPicker();
        this._showMealToast();
      } catch (e) {
        this.mealToast = e.message;
        this._showMealToast();
      } finally {
        this.mealRecording = false;
      }
    },
    _showMealToast() {
      if (this._mealToastTimer) clearTimeout(this._mealToastTimer);
      this._mealToastTimer = setTimeout(() => { this.mealToast = ''; }, 2500);
    },
  };
}

/* 新增/编辑食谱：表单 + 食材步骤动态增删 + 图片上传 + 提交 */
function editPage(isEdit, recipeId, initialProvider) {
  // 多渠道元数据：id -> { 中文名, 前端官网跳转 base, 去官网找图文字 }
  const PROVIDER_META = {
    pixabay: {
      label: 'Pixabay 英文',
      externalHint: 'API 不够准？去 Pixabay 官网找图后复制 URL 贴回来',
      buildHref: (kw) => 'https://pixabay.com/images/search/' + encodeURIComponent(kw || '') + '/?cat=food&image_type=photo&order=popular',
    },
    pixabay_zh: {
      label: 'Pixabay 中文',
      externalHint: 'API 不够准？去 Pixabay 中文官网找图后复制 URL 贴回来',
      buildHref: (kw) => 'https://pixabay.com/zh/images/search/' + encodeURIComponent(kw || '') + '/?cat=food&image_type=photo&order=popular',
    },
    wikimedia: {
      label: 'Wikimedia Commons',
      externalHint: 'API 不够准？去 Wikimedia Commons 官网找图后复制图片链接贴回来',
      buildHref: (kw) => 'https://commons.wikimedia.org/w/index.php?search=' + encodeURIComponent((kw || '') + ' food') + '&title=Special:MediaSearch&type=image',
    },
  };
  const PROVIDER_ORDER = ['pixabay', 'pixabay_zh', 'wikimedia'];
  const DIET_TAGS = ['辣', '海鲜', '坚果', '鸡蛋', '牛奶', '麸质', '花生', '素食', '高糖'];
  const pickMeta = (p) => PROVIDER_META[p] || PROVIDER_META.pixabay;

  return {
    isEdit: !!isEdit,
    recipeId: recipeId || null,
    DIET_TAGS,
    saving: false,
    error: '',
    dragOver: false,
    uploading: false,
    form: {
      title: '', description: '', category: '', servings: 2,
      prep_time: null, cook_time: null, image_path: '',
      meal_tags: ['lunch', 'dinner'],
      diet_tags: [],
    },
    ingredients: [{ name: '', amount: '', unit: '' }],
    steps: [{ description: '' }],
    /* 图片搜索状态：新增 provider/page/external* 等字段（不用 getter，改用普通字段 + _applyProviderMeta 统一刷新） */
    imgSearch: {
      open: false,
      loading: false,
      results: [],
      manualMode: false,
      manualUrl: '',
      keyword: '',
      hasSearched: false,
      page: 1,
      per_page: 9,
      provider: (initialProvider || 'pixabay').trim() || 'pixabay',
      providerLabel: 'Pixabay 英文',
      externalHint: 'API 不够准？去 Pixabay 官网找图后复制 URL 贴回来',
      externalHref: 'https://pixabay.com/images/search/',
      _fallbackKw: '',
    },
    /* 导入菜谱弹窗状态 */
    recipeImport: {
      open: false,
      tab: 'search',
      keyword: '',
      searched: false,
      loading: false,
      results: [],
      selected: null,
      pasteText: '',
      pasteLoading: false,
      ocrLoading: false,
      ocrMsg: '',
      parsed: null,
      // 中英转换：搜索返回的英文查询词与原始中文
      enQueries: [],
      zhKeyword: '',
      enMode: false,
    },

    async init() {
      if (!RecipeApp.getToken()) { window.location.href = '/login'; return; }
      if (this.isEdit && this.recipeId) {
        try {
          const res = await RecipeApp.api('/api/recipes/' + this.recipeId);
          if (!res.ok) throw new Error('加载失败');
          const r = await res.json();
          this.form.title = r.title || '';
          this.form.description = r.description || '';
          this.form.category = r.category || '';
          this.form.servings = r.servings || 2;
          this.form.prep_time = r.prep_time;
          this.form.cook_time = r.cook_time;
          this.form.image_path = r.image_path || '';
          this.form.diet_tags = r.diet_tags || [];
          if (r.meal_tags && r.meal_tags.length) {
            this.form.meal_tags = r.meal_tags;
          } else {
            const cat = (r.category || '').trim();
            if (cat === '早餐') this.form.meal_tags = ['breakfast'];
            else if (cat === '午餐') this.form.meal_tags = ['lunch'];
            else if (cat === '晚餐') this.form.meal_tags = ['dinner'];
            else this.form.meal_tags = ['lunch', 'dinner'];
          }
          this.ingredients = (r.ingredients && r.ingredients.length)
            ? r.ingredients.map(i => ({ name: i.name, amount: i.amount || '', unit: i.unit || '' }))
            : [{ name: '', amount: '', unit: '' }];
          this.steps = (r.steps && r.steps.length)
            ? r.steps.map(s => ({ description: s.description }))
            : [{ description: '' }];
        } catch (e) { this.error = e.message; }
      }
    },

    /* 餐次标签切换 */
    toggleMealTag(tag) {
      const idx = this.form.meal_tags.indexOf(tag);
      if (idx >= 0) this.form.meal_tags.splice(idx, 1);
      else this.form.meal_tags.push(tag);
    },
    /* 忌口标签切换 */
    toggleDietTag(tag) {
      const idx = this.form.diet_tags.indexOf(tag);
      if (idx >= 0) this.form.diet_tags.splice(idx, 1);
      else this.form.diet_tags.push(tag);
    },
    /* 自定义忌口标签 */
    dietCustom: '',
    addDietTag() {
      const t = (this.dietCustom || '').trim();
      this.dietCustom = '';
      if (!t) return;
      if (t.length > 12) { this.error = '忌口标签最多 12 个字'; return; }
      if (this.form.diet_tags.length >= 20) { this.error = '忌口标签最多 20 个'; return; }
      if (!this.form.diet_tags.includes(t)) this.form.diet_tags.push(t);
    },
    removeDietTag(tag) {
      const idx = this.form.diet_tags.indexOf(tag);
      if (idx >= 0) this.form.diet_tags.splice(idx, 1);
    },
    /* 食材行 */
    addIngredient() { this.ingredients.push({ name: '', amount: '', unit: '' }); this.refreshIcons(); },
    removeIngredient(i) { if (this.ingredients.length > 1) this.ingredients.splice(i, 1); this.refreshIcons(); },
    /* 步骤行 */
    addStep() { this.steps.push({ description: '' }); this.refreshIcons(); },
    removeStep(i) { if (this.steps.length > 1) this.steps.splice(i, 1); this.refreshIcons(); },
    /* Alpine x-for 动态新增的 <i data-lucide> 需要重新调用 lucide.createIcons() 才会渲染成 SVG */
    refreshIcons() {
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },

    /* 图片上传：拖拽 + 点击 */
    onDrop(e) {
      this.dragOver = false;
      const f = e.dataTransfer.files && e.dataTransfer.files[0];
      if (f) this.uploadFile(f);
    },
    onFilePicked(e) {
      const f = e.target.files && e.target.files[0];
      if (f) this.uploadFile(f);
    },
    async uploadFile(file) {
      this.uploading = true;
      try {
        const fd = new FormData();
        fd.append('file', file);
        const res = await RecipeApp.api('/api/upload', { method: 'POST', body: fd });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '上传失败');
        this.form.image_path = data.path;
      } catch (e) { this.error = e.message; }
      finally { this.uploading = false; }
    },
    clearImage() { this.form.image_path = ''; },

    /* ===== 导入菜谱（TheMealDB 搜索 + 粘贴解析） ===== */
    openRecipeImport() {
      this.recipeImport.open = true;
      this.recipeImport.keyword = (this.form.title || '').trim();
      this.recipeImport.searched = false;
      this.recipeImport.results = [];
      this.recipeImport.selected = null;
      this.recipeImport.parsed = null;
      this.recipeImport.enQueries = [];
      this.recipeImport.zhKeyword = '';
      this.recipeImport.enMode = false;
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    closeRecipeImport() {
      this.recipeImport.open = false;
      this.recipeImport.selected = null;
      this.recipeImport.parsed = null;
    },
    async doRecipeSearch() {
      const kw = (this.recipeImport.keyword || '').trim();
      if (!kw) return;
      this.recipeImport.loading = true;
      this.recipeImport.searched = true;
      this.recipeImport.results = [];
      this.recipeImport.selected = null;
      try {
        const res = await RecipeApp.api('/api/recipe-api/search?keyword=' + encodeURIComponent(kw));
        const d = res.ok ? await res.json() : null;
        if (Array.isArray(d)) {
          this.recipeImport.results = d;
          this.recipeImport.enQueries = [];
        } else {
          this.recipeImport.results = (d && d.items) || [];
          this.recipeImport.enQueries = (d && d.en_queries) || [];
          // 在中文模式下记住原始中文关键词，供"切回中文"用
          if ((d && d.zh_keyword) || /\p{Script=Han}/u.test(kw)) {
            this.recipeImport.zhKeyword = kw;
          }
        }
      } catch (e) {
        this.recipeImport.results = [];
      } finally {
        this.recipeImport.loading = false;
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
      }
    },
    /** 中英转换：中文↔英文搜索词切换（TheMealDB 按英文搜索最准） */
    toggleZhEn() {
      const r = this.recipeImport;
      if (!r.enMode && r.zhKeyword && r.enQueries.length) {
        r.keyword = r.enQueries[0];
        r.enMode = true;
      } else if (r.enMode && r.zhKeyword) {
        r.keyword = r.zhKeyword;
        r.enMode = false;
      } else {
        return;
      }
      this.doRecipeSearch();
    },
    /** 把推荐的英文查询词填入输入框（不立即搜索，方便手动微调） */
    fillEnQuery() {
      const r = this.recipeImport;
      if (r.enQueries.length) {
        r.keyword = r.enQueries.join(' ');
        r.enMode = true;
      }
    },
    async selectRecipe(r) {
      this.recipeImport.selected = null;
      try {
        const res = await RecipeApp.api('/api/recipe-api/prepare', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            id: r.id, title: r.title, category: r.category, area: r.area,
            thumb: r.thumb, ingredients: r.ingredients, steps: r.steps,
          }),
        });
        if (res.ok) this.recipeImport.selected = await res.json();
      } catch (e) { /* 忽略 */ }
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    importSelected() {
      if (!this.recipeImport.selected) return;
      this.applyImported(this.recipeImport.selected);
      this.closeRecipeImport();
    },
    async ocrUpload(ev) {
      const f = ev.target.files && ev.target.files[0];
      if (!f) return;
      this.recipeImport.ocrLoading = true;
      this.recipeImport.ocrMsg = '';
      try {
        const fd = new FormData();
        fd.append('file', f);
        const res = await RecipeApp.api('/api/ocr', { method: 'POST', body: fd });
        if (res.ok) {
          const d = await res.json();
          this.recipeImport.pasteText = d.text || '';
          this.recipeImport.ocrMsg = d.lines ? ('已识别 ' + d.lines + ' 行，点击「解析」填充表单') : '未能识别出文字，请换一张更清晰的照片';
        } else {
          const d = await res.json().catch(() => ({}));
          this.recipeImport.ocrMsg = d.detail || '识别失败，请重试';
        }
      } catch (e) {
        this.recipeImport.ocrMsg = '识别失败，请重试';
      } finally {
        this.recipeImport.ocrLoading = false;
        if (ev.target) ev.target.value = '';
      }
    },
    async doPasteParse() {
      const text = (this.recipeImport.pasteText || '').trim();
      if (!text) return;
      this.recipeImport.pasteLoading = true;
      this.recipeImport.parsed = null;
      try {
        const res = await RecipeApp.api('/api/recipe-api/parse-paste', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: text }),
        });
        if (res.ok) this.recipeImport.parsed = await res.json();
      } catch (e) {
        this.recipeImport.parsed = null;
      } finally {
        this.recipeImport.pasteLoading = false;
      }
    },
    importParsed() {
      const p = this.recipeImport.parsed;
      if (!p || !p.title) return;
      this.applyImported({
        title: p.title,
        category: '',
        image_path: this.form.image_path,
        servings: 2,
        meal_tags: this.form.meal_tags.length ? this.form.meal_tags : ['lunch', 'dinner'],
        ingredients: (p.ingredients || []).map(i => ({ name: i.name || '', amount: i.amount || '', unit: '' })),
        steps: (p.steps || []).map(s => ({ description: s })),
        original_title: '',
      });
      this.closeRecipeImport();
    },
    /** 把导入内容填进表单（保留原有餐次/份数/描述直到明确覆盖） */
    applyImported(p) {
      if (!p) return;
      if (p.title) this.form.title = p.title;
      if (p.category) this.form.category = p.category;
      if (p.image_path) this.form.image_path = p.image_path;
      if (p.meal_tags && p.meal_tags.length) this.form.meal_tags = p.meal_tags;
      if (p.ingredients && p.ingredients.length) {
        this.ingredients = p.ingredients.map(i => ({
          name: i.name || i.ingredient || '',
          amount: i.amount || i.measure || '',
          unit: i.unit || '',
        }));
      }
      if (p.steps && p.steps.length) {
        this.steps = p.steps.map(s => typeof s === 'string' ? { description: s } : { description: s.description || '' });
      }
      if (p.original_title && !this.form.description) {
        this.form.description = '（来源：' + p.original_title + '）';
      }
      this.refreshIcons();
    },

    /* ===== 多渠道图片搜索 / 手动输入 / 分页 ===== */
    /** 根据当前 provider + 关键词刷新 providerLabel/externalHint/externalHref 三个普通字段 */
    _applyProviderMeta() {
      const meta = pickMeta(this.imgSearch.provider);
      this.imgSearch.providerLabel = meta.label;
      this.imgSearch.externalHint = meta.externalHint;
      const kw = (this.imgSearch.keyword || '').trim() || (this.imgSearch._fallbackKw || '');
      this.imgSearch.externalHref = meta.buildHref(kw);
    },
    /** 临时在三大渠道间循环切换（只影响本次弹窗搜索，不改系统设置） */
    switchProvider() {
      const idx = PROVIDER_ORDER.indexOf(this.imgSearch.provider);
      const next = PROVIDER_ORDER[(idx + 1) % PROVIDER_ORDER.length];
      this.imgSearch.provider = next;
      this._applyProviderMeta();
      // 如果已搜过，则自动用新渠道按当前关键词+分页重搜一次
      if (this.imgSearch.hasSearched && (this.imgSearch.keyword || this.form.title)) {
        this.doImageSearch(1);
      } else {
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
      }
    },
    /**
     * 打开图片搜索弹窗：
     * - 如果食谱标题已有内容 → 预填到关键词并立即自动搜一次（第 1 页）
     * - 如果没有标题 → 只打开弹窗，让用户在新的搜索框里自行输入关键词再搜
     */
    openImageSearch() {
      this.imgSearch.open = true;
      this.imgSearch.results = [];
      this.imgSearch.manualUrl = '';
      this.imgSearch.manualMode = false;
      this.imgSearch.hasSearched = false;
      this.imgSearch.page = 1;
      const titleKw = (this.form.title || '').trim();
      this.imgSearch._fallbackKw = titleKw;
      if (titleKw) {
        this.imgSearch.keyword = titleKw;
        // 下一帧再执行，确保 Alpine 渲染完输入框后才显示 loading
        this.$nextTick(() => this.doImageSearch(1));
      } else {
        this.imgSearch.keyword = '';
        this.imgSearch.loading = false;
      }
      this._applyProviderMeta();
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    /** 用户在弹窗搜索框里回车 / 点「搜索」按钮时触发 —— 永远从第 1 页开始 */
    submitKeywordSearch() {
      const kw = (this.imgSearch.keyword || '').trim();
      if (!kw) return;
      this.doImageSearch(1);
    },
    /** 上一页 */
    prevPage() {
      if (this.imgSearch.page <= 1) return;
      this.doImageSearch(this.imgSearch.page - 1);
    },
    /** 下一页：只有当本页刚好满 9 张时才允许前进（避免无限翻空页） */
    nextPage() {
      if (this.imgSearch.results.length < 9) return;
      this.doImageSearch(this.imgSearch.page + 1);
    },
    /**
     * 核心：按关键词 + 分页 + 当前 provider 执行搜索。
     * 关键词来源：优先取弹窗内 imgSearch.keyword；没有时退回到 form.title。
     */
    async doImageSearch(targetPage) {
      const page = Math.max(1, Number(targetPage) || 1);
      const kw = ((this.imgSearch.keyword || '').trim() || (this.form.title || '').trim());
      this.imgSearch.loading = true;
      this.imgSearch.results = [];
      this.imgSearch.manualMode = false;
      this.imgSearch.hasSearched = true;
      this.imgSearch.page = page;
      this.imgSearch._fallbackKw = kw;
      this._applyProviderMeta();
      if (!kw) {
        this.imgSearch.loading = false;
        this.imgSearch.manualMode = true;
        return;
      }
      try {
        const params = new URLSearchParams();
        params.set('keyword', kw);
        params.set('page', String(page));
        params.set('per_page', String(this.imgSearch.per_page || 9));
        params.set('provider', this.imgSearch.provider);
        const res = await RecipeApp.api('/api/search-image?' + params.toString());
        if (res.ok) {
          this.imgSearch.results = await res.json();
        } else {
          this.imgSearch.results = [];
        }
      } catch (e) {
        this.imgSearch.results = [];
      } finally {
        this.imgSearch.loading = false;
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
        // 无结果（未配置 Key、网络失败、没搜到）→ 自动展开手动输入
        if (!this.imgSearch.results || this.imgSearch.results.length === 0) {
          this.imgSearch.manualMode = true;
        }
      }
    },
    closeImageSearch() {
      this.imgSearch.open = false;
    },
    selectSearchImage(url) {
      if (!url || !url.trim()) return;
      this.form.image_path = url.trim();
      this.closeImageSearch();
    },

    /* 提交：新建 POST /api/recipes，编辑 PUT /api/recipes/{id} */
    async submit() {
      this.error = '';
      if (!this.form.title.trim()) { this.error = '请填写食谱标题'; return; }
      if (!this.form.meal_tags || this.form.meal_tags.length === 0) { this.error = '请至少选择一个适用餐次'; return; }
      this.saving = true;
      try {
        const payload = {
          title: this.form.title.trim(),
          description: this.form.description.trim() || null,
          category: this.form.category || null,
          servings: Number(this.form.servings) || 2,
          prep_time: this.form.prep_time === null ? null : Number(this.form.prep_time),
          cook_time: this.form.cook_time === null ? null : Number(this.form.cook_time),
          image_path: this.form.image_path || null,
          meal_tags: this.form.meal_tags,
          diet_tags: this.form.diet_tags || [],
          ingredients: this.ingredients
            .filter(i => i.name.trim())
            .map(i => ({ name: i.name.trim(), amount: i.amount.trim() || null, unit: i.unit.trim() || null })),
          steps: this.steps.filter(s => s.description.trim()).map((s, idx) => ({
            step_number: idx + 1, description: s.description.trim(),
          })),
        };
        const url = this.isEdit ? '/api/recipes/' + this.recipeId : '/api/recipes';
        const method = this.isEdit ? 'PUT' : 'POST';
        const res = await RecipeApp.api(url, {
          method: method,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '保存失败');
        window.location.href = '/recipes/' + data.id;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.saving = false;
      }
    },
  };
}

/* 用户管理：添加用户弹窗（含权限选择） + 删除用户（列表服务端渲染） */
function adminPage() {
  return {
    activeTab: 'users',
    showAdd: false,
    creating: false,
    addError: '',
    newUser: { username: '', password: '', is_admin: false, display_name: '', avatar: '' },
    // 系统设置
    saving: false,
    saveMsg: '',
    saveErr: '',
    settingsForm: { public_base_url: '', site_name: '', recipe_source: 'themealdb', recipe_translate: '1', github_repo: '', server_version: '' },
    // 代理测试状态
    proxyTest: { loading: false, msg: '', ok: null },
    // 代理测试目标 URL：预设下拉选择
    proxyTestSel: 'https://pixabay.com/api/docs/',
    proxyCustom: false,
    // 登录背景图弹层状态
    loginBg: {
      open: false, loading: false, results: [], keyword: '', page: 1,
      manualUrl: '', manualMode: false, hasSearched: false, uploading: false,
    },
    FAMILY_PRESETS: [
      { key: 'dad', name: '爸爸', emoji: '👨' },
      { key: 'mom', name: '妈妈', emoji: '👩' },
      { key: 'grandpa', name: '爷爷', emoji: '👴' },
      { key: 'grandma', name: '奶奶', emoji: '👵' },
      { key: 'brother', name: '哥哥', emoji: '🧑' },
      { key: 'sister', name: '姐姐', emoji: '👧' },
      { key: 'little_brother', name: '弟弟', emoji: '👦' },
      { key: 'little_sister', name: '妹妹', emoji: '🧒' },
      { key: 'son', name: '儿子', emoji: '👶' },
      { key: 'daughter', name: '女儿', emoji: '👧' },
    ],

    openAdd() {
      this.addError = '';
      this.newUser = { username: '', password: '', is_admin: false, display_name: '', avatar: '' };
      this.showAdd = true;
    },
    toggleAvoidTag(tag) {
      const idx = this.form.avoid_tags.indexOf(tag);
      if (idx >= 0) this.form.avoid_tags.splice(idx, 1);
      else this.form.avoid_tags.push(tag);
    },
    avoidCustom: '',
    addAvoidTag() {
      const t = (this.avoidCustom || '').trim();
      this.avoidCustom = '';
      if (!t) return;
      if (t.length > 12) { this.error = '忌口标签最多 12 个字'; return; }
      if (this.form.avoid_tags.length >= 20) { this.error = '忌口标签最多 20 个'; return; }
      if (!this.form.avoid_tags.includes(t)) this.form.avoid_tags.push(t);
    },
    removeAvoidTag(tag) {
      const idx = this.form.avoid_tags.indexOf(tag);
      if (idx >= 0) this.form.avoid_tags.splice(idx, 1);
    },

    selectPreset(p) {
      this.newUser.display_name = p.name;
      this.newUser.avatar = p.key;
    },
    closeAdd() {
      this.showAdd = false;
    },

    async createUser() {
      this.addError = '';
      this.creating = true;
      try {
        const res = await RecipeApp.api('/api/users', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(this.newUser),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '创建失败');
        this.showAdd = false;
        this.newUser = { username: '', password: '', is_admin: false, display_name: '', avatar: '' };
        window.location.reload();
      } catch (e) {
        this.addError = e.message;
      } finally {
        this.creating = false;
      }
    },

    askDelete(userId, username) {
      window.__confirm({
        title: '删除用户',
        message: '确定删除用户「' + username + '」吗？其创建的食谱会保留。',
        onOk: async () => {
          try {
            const res = await RecipeApp.api('/api/users/' + userId, { method: 'DELETE' });
            if (!res.ok && res.status !== 204) {
              const d = await res.json().catch(() => ({}));
              throw new Error(d.detail || '删除失败');
            }
            window.location.reload();
          } catch (e) {
            window.__confirm({ title: '删除失败', message: e.message, onOk: () => {} });
          }
        },
      });
    },

    /* 系统设置保存 */
    async saveSettings() {
      this.saveErr = '';
      this.saveMsg = '';
      this.saving = true;
      try {
        if (this.settingsForm.public_base_url && !/^https?:\/\/.+/.test(this.settingsForm.public_base_url)) {
          throw new Error('服务器对外地址必须以 http:// 或 https:// 开头');
        }
        const body = { ...this.settingsForm };
        const res = await RecipeApp.api('/api/system/settings/admin', {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data.detail || '保存失败');
        this.saveMsg = '✅ 已保存，正在应用新设置…';
        // 刷新页面以应用新设置，但保持停留在当前 Tab（系统设置 / API 管理）
        setTimeout(() => { window.location.href = '/admin?tab=' + (this.activeTab || 'settings'); }, 700);
      } catch (e) {
        this.saveErr = e.message;
      } finally {
        this.saving = false;
      }
    },

    /* ===== 系统设置：代理测试 ===== */
    /** 代理测试目标 URL 下拉变化：预设直接写入；自定义则显示输入框 */
    onProxyTestSel() {
      const presets = [
        'https://pixabay.com/api/docs/',
        'https://commons.wikimedia.org/w/api.php?action=query&meta=siteinfo',
        'https://www.google.com',
        'https://github.com',
        'https://www.baidu.com',
      ];
      if (this.proxyTestSel === '__custom__') { this.proxyCustom = true; return; }
      this.proxyCustom = false;
      this.settingsForm.proxy_test_url = this.proxyTestSel;
    },
    async runProxyTest() {
      this.proxyTest.loading = true;
      this.proxyTest.msg = '正在测试…';
      this.proxyTest.ok = null;
      try {
        // 先把表单里正在编辑的值临时保存一次，再调用测试接口
        // （这样用户不用先点"保存设置"再测，编辑中就能直接测）
        const payload = {
          proxy_url: (this.settingsForm.proxy_url || '').trim(),
          proxy_test_url: (this.settingsForm.proxy_test_url || '').trim() || 'https://pixabay.com/api/docs/',
        };
        // 先 PUT 保存（覆盖写入这两个字段；即使失败也不影响 test 提示）
        try {
          const saveRes = await RecipeApp.api('/api/system/settings/admin', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
          });
          saveRes.ok; // eslint-disable-line
        } catch (_) { /* 忽略保存错误，继续用旧值测 */ }
        const res = await RecipeApp.api('/api/system/proxy/test', { method: 'POST' });
        const d = await res.json().catch(() => ({}));
        if (res.ok && d.ok) {
          this.proxyTest.ok = true;
          this.proxyTest.msg = '✅ 连通成功：HTTP ' + (d.http_code || '200') + ' · 耗时 ' + (d.elapsed_ms || 0) + ' ms' + (d.proxy === '' && d.note ? '（未使用代理）' : '');
        } else {
          this.proxyTest.ok = false;
          this.proxyTest.msg = '❌ 连通失败：' + (d.error || d.detail || '未知错误');
        }
      } catch (e) {
        this.proxyTest.ok = false;
        this.proxyTest.msg = '❌ 请求异常：' + e.message;
      } finally {
        this.proxyTest.loading = false;
      }
    },

    /* ===== 登录背景图：复用 /api/search-image 进行搜索（支持分页 per_page=9） ===== */
    async loginBgSearch(page) {
      const kw = (this.loginBg.keyword || '').trim();
      const p = Math.max(1, Number(page) || 1);
      if (!kw) {
        this.loginBg.open = true;
        return;
      }
      this.loginBg.loading = true;
      this.loginBg.hasSearched = true;
      this.loginBg.page = p;
      this.loginBg.results = [];
      try {
        const params = new URLSearchParams();
        params.set('keyword', kw);
        params.set('page', String(p));
        params.set('per_page', '9');
        // 登录背景用系统设置中当前的 image_provider（由 settingsForm.image_provider 提供临时覆盖）
        if (this.settingsForm && this.settingsForm.image_provider) {
          params.set('provider', this.settingsForm.image_provider);
        }
        const res = await RecipeApp.api('/api/search-image?' + params.toString());
        if (res.ok) {
          this.loginBg.results = await res.json();
        } else {
          this.loginBg.results = [];
        }
      } catch (e) {
        this.loginBg.results = [];
      } finally {
        this.loginBg.loading = false;
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
      }
    },

    /* ===== 登录背景图：上传本地图片 → 走 /api/upload → 把返回的 path 填到 settingsForm ===== */
    async loginBgUpload(file) {
      if (!file) return;
      this.loginBg.uploading = true;
      try {
        const fd = new FormData();
        fd.append('file', file);
        const res = await RecipeApp.api('/api/upload', { method: 'POST', body: fd });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data.detail || '上传失败');
        if (!data.path) throw new Error('上传返回缺少 path');
        // data.path 可能是相对路径，需要转成绝对 URL 给登录页展示
        let url = data.path;
        if (url && /^\/[^\/]/.test(url) && this.settingsForm && this.settingsForm.public_base_url) {
          const base = this.settingsForm.public_base_url.replace(/\/$/, '');
          url = base + url;
        }
        this.settingsForm.login_bg_image = url;
        this.loginBg.open = false;
      } catch (e) {
        alert('登录背景图上传失败：' + e.message);
      } finally {
        this.loginBg.uploading = false;
      }
    },
  };
}

/* 关于页：展示设计理念 / 使用方法 / 版本更新(GitHub Releases) / 客户端配置二维码 */
function aboutPage() {
  const user = RecipeApp.getUser() || {};
  return {
    baseUrl: '',
    qrVisible: false,
    is_admin: user.is_admin || false,
    release: null,       // /api/app/check 结果
    releaseLoading: false,
    updateChecked: false, // 是否已点过「检测更新」
    updateState: '',      // '' / latest / outdated / unconfigured
    updateLatest: '',     // 服务器落后时的最新版本号（不含 v 前缀）
    updating: false,      // 是否在在线更新中
    async init() {
      // 公开设置接口（无需管理员权限），拿服务器对外地址用于拼二维码
      try {
        const res = await RecipeApp.api('/api/system/settings');
        if (res.ok) {
          const d = await res.json();
          this.baseUrl = d.public_base_url || '';
        }
      } catch (e) { /* 忽略 */ }
      // GitHub 最新版本（公开接口，未配置/失败时静默）
      this.releaseLoading = true;
      try {
        const res = await fetch('/api/app/check');
        if (res.ok) this.release = await res.json();
      } catch (e) { this.release = null; }
      finally { this.releaseLoading = false; }
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },
    /* 点击「服务器版本」按钮：强制刷新 GitHub 最新版本并比对本地版本 */
    async checkUpdate() {
      this.releaseLoading = true;
      this.updateChecked = false;
      try {
        const res = await fetch('/api/app/check?force=true');
        if (res.ok) {
          this.release = await res.json();
          this.updateChecked = true;
          if (this.release && this.release.configured && !this.release.error) {
            const cur = this._parseVer(this.release.server_version);
            const latest = this._parseVer('v' + this.release.version);
            if (cur === null || latest === null) {
              this.updateState = 'unconfigured';
            } else if (cur < latest) {
              this.updateState = 'outdated';
              this.updateLatest = this.release.version;
            } else {
              this.updateState = 'latest';
            }
          } else {
            this.updateState = 'unconfigured';
          }
        } else {
          this.updateChecked = true;
          this.updateState = 'unconfigured';
        }
      } catch (e) {
        this.updateChecked = true;
        this.updateState = 'unconfigured';
      } finally {
        this.releaseLoading = false;
        this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
      }
    },
    /* 在线更新：拉取最新镜像并重启服务 */
    async doUpdate() {
      this.updating = true;
      try {
        const res = await RecipeApp.api('/api/system/update', { method: 'POST' });
        if (res.ok) {
          alert('更新已触发，服务正在重启...\n\n请稍后刷新页面。');
          window.location.reload();
        } else {
          const err = await res.json().catch(() => ({}));
          alert('更新失败：' + (err.detail || '未知错误'));
        }
      } catch (e) {
        alert('更新请求失败：' + e.message);
      } finally {
        this.updating = false;
      }
    },
    /* 把 v0.0.1 / 0.0.1 解析成可比较的整数（忽略位数差异） */
    _parseVer(v) {
      if (!v) return null;
      const m = String(v).replace(/^v/i, '').match(/(\d+)\.(\d+)\.(\d+)/);
      if (!m) return null;
      return (+m[1]) * 1000000 + (+m[2]) * 1000 + (+m[3]);
    },
    copyConfig() {
      if (!this.baseUrl) return;
      const payload = JSON.stringify({ base_url: this.baseUrl });
      navigator.clipboard && navigator.clipboard.writeText(payload).then(
        () => alert('配置已复制到剪贴板：\n' + payload),
        () => prompt('手动复制下面的配置字符串：', payload),
      );
    },
    /* 生成二维码：懒加载 qrcode.js CDN */
    async showQR() {
      if (!this.baseUrl) return;
      this.qrVisible = true;
      await this.$nextTick();
      const draw = () => {
        const payload = JSON.stringify({ base_url: this.baseUrl });
        try {
          this.$refs.qrCanvas.innerHTML = '';
          new QRCode(this.$refs.qrCanvas, {
            text: payload,
            width: 168,
            height: 168,
            correctLevel: QRCode.CorrectLevel.M,
          });
        } catch (e) {
          this.$refs.qrCanvas.innerHTML =
            '<div class="w-full h-full flex items-center justify-center fr-caption text-muted-foreground text-center p-2">' +
            '二维码库加载失败，请使用「复制配置 URL」按钮</div>';
        }
      };
      if (window.QRCode) { draw(); return; }
      if (!document.getElementById('qrjs-lib')) {
        const s = document.createElement('script');
        s.id = 'qrjs-lib';
        s.src = 'https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js';
        s.onload = draw;
        s.onerror = draw;
        document.head.appendChild(s);
      }
    },
  };
}

/* 个人资料页：上传头像 + 修改昵称 + 修改密码 */
function profilePage() {
  return {
    form: { display_name: '', avatar: '', carousel_type: 'most_cooked', carousel_limit: 10, username: '', avatar_path: '', avoid_tags: [] },
    AVOID_TAGS: ['辣', '海鲜', '坚果', '鸡蛋', '牛奶', '麸质', '花生', '素食', '高糖'],
    FAMILY_PRESETS: [
      { key: 'dad', name: '爸爸', emoji: '👨' },
      { key: 'mom', name: '妈妈', emoji: '👩' },
      { key: 'grandpa', name: '爷爷', emoji: '👴' },
      { key: 'grandma', name: '奶奶', emoji: '👵' },
      { key: 'brother', name: '哥哥', emoji: '🧑' },
      { key: 'sister', name: '姐姐', emoji: '👧' },
      { key: 'little_brother', name: '弟弟', emoji: '👦' },
      { key: 'little_sister', name: '妹妹', emoji: '🧒' },
      { key: 'son', name: '儿子', emoji: '👶' },
      { key: 'daughter', name: '女儿', emoji: '👧' },
    ],
    saving: false,
    uploading: false,
    error: '',
    success: false,
    pwd: { old: '', new: '', confirm: '' },
    pwdSaving: false,
    pwdError: '',
    pwdSuccess: false,

    async init() {
      try {
        const res = await RecipeApp.api('/api/users/profile');
        if (!res.ok) throw new Error('加载失败');
        const u = await res.json();
        this.form.username = u.username || '';
        this.form.display_name = u.display_name || '';
        this.form.avatar = u.avatar || '';
        this.form.avatar_path = u.avatar_path || '';
        this.form.carousel_type = u.carousel_type || 'most_cooked';
        this.form.carousel_limit = u.carousel_limit || 10;
        this.form.avoid_tags = u.avoid_tags || [];
      } catch (e) { this.error = e.message; }
    },

    selectPreset(p) {
      this.form.display_name = p.name;
      this.form.avatar = p.key;
    },

    async onAvatarPicked(e) {
      const f = e.target.files && e.target.files[0];
      if (!f) return;
      this.error = '';
      this.uploading = true;
      try {
        const fd = new FormData();
        fd.append('file', f);
        const res = await RecipeApp.api('/api/upload', { method: 'POST', body: fd });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '上传失败');
        this.form.avatar = data.path;
      } catch (e) { this.error = e.message; }
      finally { this.uploading = false; }
    },

    async save() {
      this.error = '';
      this.success = false;
      if (!this.form.display_name.trim()) { this.error = '请填写显示名'; return; }
      this.saving = true;
      try {
        const res = await RecipeApp.api('/api/users/profile', {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            display_name: this.form.display_name.trim(),
            username: this.form.username.trim() || undefined,
            avatar: this.form.avatar || null,
            carousel_type: this.form.carousel_type,
            carousel_limit: Number(this.form.carousel_limit) || 10,
            avoid_tags: this.form.avoid_tags || [],
          }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '保存失败');
        const cur = RecipeApp.getUser() || {};
        RecipeApp.setUser(Object.assign({}, cur, {
          username: data.username || this.form.username,
          display_name: data.display_name,
          avatar: data.avatar,
        }));
        this.success = true;
        // 如果账户名改了，需要重新登录
        if (data.username && data.username !== cur.username) {
          setTimeout(() => {
            RecipeApp.clear();
            window.location.href = '/login';
          }, 1000);
        } else {
          setTimeout(() => window.location.reload(), 600);
        }
      } catch (e) {
        this.error = e.message;
      } finally {
        this.saving = false;
      }
    },

    async changePassword() {
      this.pwdError = '';
      this.pwdSuccess = false;
      if (!this.pwd.old || !this.pwd.new) { this.pwdError = '请填写原密码和新密码'; return; }
      if (this.pwd.new !== this.pwd.confirm) { this.pwdError = '两次输入的新密码不一致'; return; }
      this.pwdSaving = true;
      try {
        const res = await RecipeApp.api('/api/users/me/password', {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ old_password: this.pwd.old, new_password: this.pwd.new }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || '修改失败');
        this.pwd = { old: '', new: '', confirm: '' };
        this.pwdSuccess = true;
      } catch (e) {
        this.pwdError = e.message;
      } finally {
        this.pwdSaving = false;
      }
    },
  };
}

/* 首页轮播组件 */
function carouselComponent() {
  return {
    items: [],
    loading: true,
    currentIndex: 0,
    timer: null,
    paused: false,

    async init() {
      this.loading = true;
      try {
        const res = await RecipeApp.api('/api/recipes/carousel');
        if (res.ok) {
          this.items = await res.json();
        } else {
          this.items = [];
        }
      } catch (e) {
        this.items = [];
      } finally {
        this.loading = false;
      }
      this.startAutoPlay();
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },

    next() {
      if (this.items.length === 0) return;
      this.currentIndex = (this.currentIndex + 1) % this.items.length;
    },

    prev() {
      if (this.items.length === 0) return;
      this.currentIndex = (this.currentIndex - 1 + this.items.length) % this.items.length;
    },

    goTo(i) {
      this.currentIndex = i;
    },

    goToRecipe(id) {
      if (id) window.location.href = '/recipes/' + id;
    },

    startAutoPlay() {
      if (this.timer) clearInterval(this.timer);
      this.timer = setInterval(() => {
        if (!this.paused) {
          this.next();
        }
      }, 4000);
    },

    mouseEnter() {
      this.paused = true;
    },

    mouseLeave() {
      this.paused = false;
    },

    destroy() {
      if (this.timer) {
        clearInterval(this.timer);
        this.timer = null;
      }
    },
  };
}

/* 家庭日历页面 */
function calendarPage() {
  return {
    tab: 'week',
    weekDate: '',
    weekDays: [],
    monthYear: '',
    monthDays: [],
    monthStats: { totalMeals: 0, topRecipes: [] },
    mealRows: [
      { key: 'breakfast', label: '早餐', icon: 'sunrise' },
      { key: 'lunch', label: '午餐', icon: 'sun' },
      { key: 'dinner', label: '晚餐', icon: 'moon' },
    ],
    weekGrid: [],
    rebuildWeekGrid() {
      const rows = [];
      for (const row of this.mealRows) {
        rows.push({ type: 'label', label: row.label, icon: row.icon });
        for (let i = 0; i < 7; i++) {
          rows.push({ type: 'day', idx: i, rowKey: row.key, rowLabel: row.label });
        }
      }
      this.weekGrid = rows;
    },

    pickerOpen: false,
    pickerDate: '',
    pickerMealType: '',
    pickerResults: [],
    pickerLoading: false,
    pickerQ: '',

    shoppingOpen: false,
    shoppingItems: [],
    shoppingByDay: [],
    shoppingMode: 'merged',
    shoppingLoading: false,

    init() {
      const today = new Date();
      const yyyy = today.getFullYear();
      const mm = String(today.getMonth() + 1).padStart(2, '0');
      const dd = String(today.getDate()).padStart(2, '0');
      this.weekDate = `${yyyy}-${mm}-${dd}`;
      this.monthYear = `${yyyy}-${mm}`;
      this.fetchWeek();
      this.fetchMonth();
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },

    get weekRangeText() {
      if (!this.weekDays || this.weekDays.length === 0) return '';
      const start = this.weekDays[0];
      const end = this.weekDays[6];
      return `${start.date} ~ ${end.date}`;
    },

    get monthYearText() {
      if (!this.monthYear) return '';
      const [y, m] = this.monthYear.split('-');
      return `${y}年${parseInt(m)}月`;
    },

    addDays(dateStr, days) {
      const d = new Date(dateStr);
      d.setDate(d.getDate() + days);
      const yyyy = d.getFullYear();
      const mm = String(d.getMonth() + 1).padStart(2, '0');
      const dd = String(d.getDate()).padStart(2, '0');
      return `${yyyy}-${mm}-${dd}`;
    },

    getMonday(dateStr) {
      const d = new Date(dateStr);
      const day = d.getDay() || 7;
      return this.addDays(dateStr, 1 - day);
    },

    prevWeek() {
      this.weekDate = this.addDays(this.weekDate, -7);
      this.fetchWeek();
    },

    nextWeek() {
      this.weekDate = this.addDays(this.weekDate, 7);
      this.fetchWeek();
    },

    async fetchWeek() {
      const today = new Date().toISOString().slice(0, 10);
      const names = ['一', '二', '三', '四', '五', '六', '日'];
      const buildDefault = () => {
        const days = [];
        const monday = this.getMonday(this.weekDate);
        for (let i = 0; i < 7; i++) {
          const dStr = this.addDays(monday, i);
          const d = new Date(dStr);
          days.push({
            date: dStr,
            weekdayName: '周' + names[i],
            dayNum: d.getDate(),
            isToday: dStr === today,
            breakfast: null,
            lunch: null,
            dinner: null,
          });
        }
        return days;
      };
      try {
        const monday = this.getMonday(this.weekDate);
        const res = await RecipeApp.api('/api/calendar/week?date=' + monday);
        if (res.ok) {
          const data = await res.json();
          const apiDays = data.days || [];
          const toSlots = (arr) => (arr || []).map((x) => (x && x.recipe_id ? {
            recipe_id: x.recipe_id,
            title: x.title,
            image_path: x.image_url || x.image_path || '',
          } : null)).filter(Boolean);
          this.weekDays = apiDays.map((d, i) => {
            const dateObj = new Date(d.date);
            return {
              date: d.date,
              weekdayName: d.weekday || ('周' + names[i]),
              dayNum: dateObj.getDate(),
              isToday: d.date === today,
              breakfast: toSlots(d.breakfast),
              lunch: toSlots(d.lunch),
              dinner: toSlots(d.dinner),
            };
          });
        } else {
          this.weekDays = buildDefault();
        }
      } catch (e) {
        this.weekDays = buildDefault();
      }
      this.rebuildWeekGrid();
      this.$nextTick(() => { window.__refreshIcons(); });
    },

    prevMonth() {
      const [y, m] = this.monthYear.split('-').map(Number);
      const d = new Date(y, m - 2, 1);
      this.monthYear = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      this.fetchMonth();
    },

    nextMonth() {
      const [y, m] = this.monthYear.split('-').map(Number);
      const d = new Date(y, m, 1);
      this.monthYear = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      this.fetchMonth();
    },

    async fetchMonth() {
      try {
        const res = await RecipeApp.api('/api/calendar/month?month=' + this.monthYear);
        if (res.ok) {
          const data = await res.json();
          const apiDays = data.days || [];
          const mealsByDate = {};
          const toSlots = (arr) => (arr || []).map((x) => (x && x.recipe_id ? {
            recipe_id: x.recipe_id,
            title: x.title,
            image_path: x.image_url || '',
          } : null)).filter(Boolean);
          for (const d of apiDays) {
            mealsByDate[d.date] = {
              breakfast: toSlots(d.breakfast),
              lunch: toSlots(d.lunch),
              dinner: toSlots(d.dinner),
            };
          }
          this.buildMonthDays(mealsByDate);
          // 本月统计
          const counter = {};
          let total = 0;
          for (const d of apiDays) {
            for (const mt of ['breakfast', 'lunch', 'dinner']) {
              for (const slot of (d[mt] || [])) {
                const t = (slot && slot.title) || '';
                if (!t) continue;
                counter[t] = (counter[t] || 0) + 1;
                total += 1;
              }
            }
          }
          const topRecipes = Object.entries(counter)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5)
            .map(([name, count]) => ({ name, count, pct: total ? Math.round(count * 100 / total) : 0 }));
          this.monthStats = { totalMeals: total, topRecipes };
        } else {
          this.buildMonthDays({});
        }
      } catch (e) {
        this.buildMonthDays({});
      }
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },

    buildMonthDays(mealsByDate) {
      const [y, m] = this.monthYear.split('-').map(Number);
      const firstDay = new Date(y, m - 1, 1);
      const lastDay = new Date(y, m, 0);
      const today = new Date().toISOString().slice(0, 10);
      const days = [];
      const startWeekday = (firstDay.getDay() + 6) % 7;
      for (let i = startWeekday - 1; i >= 0; i--) {
        const d = new Date(y, m - 1, -i);
        const dStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
        days.push({ date: dStr, day: d.getDate(), inMonth: false, isToday: false, expanded: false, hasMeals: false });
      }
      for (let i = 1; i <= lastDay.getDate(); i++) {
        const dStr = `${y}-${String(m).padStart(2, '0')}-${String(i).padStart(2, '0')}`;
        const meals = mealsByDate[dStr] || {};
        const hasBreakfast = !!(meals.breakfast && meals.breakfast.length);
        const hasLunch = !!(meals.lunch && meals.lunch.length);
        const hasDinner = !!(meals.dinner && meals.dinner.length);
        days.push({
          date: dStr,
          day: i,
          inMonth: true,
          isToday: dStr === today,
          expanded: false,
          hasMeals: hasBreakfast || hasLunch || hasDinner,
          hasBreakfast,
          hasLunch,
          hasDinner,
          breakfast: meals.breakfast || null,
          lunch: meals.lunch || null,
          dinner: meals.dinner || null,
        });
      }
      const remainder = days.length % 7;
      if (remainder > 0) {
        for (let i = 1; i <= 7 - remainder; i++) {
          const d = new Date(y, m, i);
          const dStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
          days.push({ date: dStr, day: d.getDate(), inMonth: false, isToday: false, expanded: false, hasMeals: false });
        }
      }
      this.monthDays = days;
    },

    async openPicker(date, mealType) {
      this.pickerDate = date;
      this.pickerMealType = mealType;
      this.pickerQ = '';
      this.pickerOpen = true;
      this.pickerResults = [];
      this.searchPickerRecipes();
      this.$nextTick(() => { if (window.lucide) window.__refreshIcons(); });
    },

    async searchPickerRecipes() {
      this.pickerLoading = true;
      try {
        const params = new URLSearchParams();
        params.set('meal_type', this.pickerMealType);
        if (this.pickerQ.trim()) params.set('q', this.pickerQ.trim());
        const res = await RecipeApp.api('/api/recipes?' + params.toString());
        if (res.ok) {
          const data = await res.json();
          this.pickerResults = data.items || data || [];
        } else {
          this.pickerResults = [];
        }
      } catch (e) {
        this.pickerResults = [];
      } finally {
        this.pickerLoading = false;
      }
    },

    async selectRecipe(recipeId) {
      try {
        const res = await RecipeApp.api('/api/calendar/plan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            date: this.pickerDate,
            meal_type: this.pickerMealType,
            recipe_id: recipeId,
          }),
        });
        if (res.ok) {
          this.pickerOpen = false;
          this.fetchWeek();
          this.fetchMonth();
        }
      } catch (e) { /* 忽略 */ }
    },

    async cancelPlan(date, mealType, recipeId) {
      if (!window.confirm('确定取消这个预定吗？')) return;
      try {
        const params = new URLSearchParams();
        params.set('date', date);
        params.set('meal_type', mealType);
        if (recipeId) params.set('recipe_id', recipeId);
        const res = await RecipeApp.api('/api/calendar/plan?' + params.toString(), { method: 'DELETE' });
        if (res.ok || res.status === 204) {
          this.fetchWeek();
          this.fetchMonth();
        }
      } catch (e) { /* 忽略 */ }
    },

    async randomFillWeek() {
      if (!this.weekDays || this.weekDays.length === 0) return;
      const mealTypes = ['breakfast', 'lunch', 'dinner'];
      for (const day of this.weekDays) {
        for (const mt of mealTypes) {
          if (!day[mt]) {
            try {
              const params = new URLSearchParams();
              params.set('meal_type', mt);
              const res = await RecipeApp.api('/api/recipes/random?' + params.toString());
              if (res.ok) {
                const r = await res.json();
                if (r && r.id && !r.empty) {
                  await RecipeApp.api('/api/calendar/plan', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                      date: day.date,
                      meal_type: mt,
                      recipe_id: r.id,
                    }),
                  });
                }
              }
            } catch (e) { /* 忽略，继续下一个 */ }
          }
        }
      }
      this.fetchWeek();
      this.fetchMonth();
    },

    async openShopping() {
      this.shoppingOpen = true;
      this.shoppingItems = [];
      this.shoppingLoading = true;
      try {
        const monday = this.getMonday(this.weekDate);
        const res = await RecipeApp.api('/api/calendar/shopping-list?week_start=' + monday);
        if (res.ok) {
          const data = await res.json();
          this.shoppingItems = data.items || [];
          this.shoppingByDay = data.by_day || [];
        } else {
          this.shoppingItems = [];
          this.shoppingByDay = [];
        }
      } catch (e) {
        this.shoppingItems = [];
      } finally {
        this.shoppingLoading = false;
      }
    },

    closeShopping() {
      this.shoppingOpen = false;
    },
  };
}

/* 详情页点赞 + 评论 */
function likeComment() {
  return {
    recipeId: document.body.getAttribute('data-recipe-id') || (window.location.pathname.split('/').filter(Boolean).pop() || ''),
    liked: false,
    likesCount: 0,
    comments: [],
    draft: '',
    sending: false,
    async init() {
      const id = parseInt(this.recipeId, 10);
      if (!id) return;
      try {
        const res = await RecipeApp.api('/api/recipes/' + id + '/comments');
        if (res.ok) { const d = await res.json(); this.comments = d.comments || []; }
      } catch (e) {}
    },
    async toggleLike() {
      const id = parseInt(this.recipeId, 10);
      if (!id) return;
      try {
        const res = await RecipeApp.api('/api/recipes/' + id + '/like', { method: 'POST' });
        if (res.ok) {
          const d = await res.json();
          this.liked = d.liked;
          this.likesCount = d.likes_count;
        }
      } catch (e) {}
    },
    async submitComment() {
      const text = (this.draft || '').trim();
      if (!text || this.sending) return;
      this.sending = true;
      try {
        const id = parseInt(this.recipeId, 10);
        const res = await RecipeApp.api('/api/recipes/' + id + '/comments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ content: text }),
        });
        if (res.ok) {
          this.draft = '';
          await this.init();
        }
      } catch (e) {}
      finally { this.sending = false; }
    },
  };
}

/* 我的库存弹窗 */
function inventoryPanel() {
  return {
    open: false,
    loading: false,
    items: [],
    form: { name: '', amount: '', unit: '' },
    adding: false,
    async load() {
      this.loading = true;
      try {
        const res = await RecipeApp.api('/api/inventory');
        if (res.ok) {
          const d = await res.json();
          this.items = d.items || [];
        } else { this.items = []; }
      } catch (e) { this.items = []; }
      finally { this.loading = false; }
    },
    async add() {
      const name = (this.form.name || '').trim();
      if (!name) return;
      this.adding = true;
      try {
        const res = await RecipeApp.api('/api/inventory', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name: name, amount: this.form.amount || null, unit: this.form.unit || null }),
        });
        if (res.ok) {
          this.form = { name: '', amount: '', unit: '' };
          await this.load();
        }
      } catch (e) {}
      finally { this.adding = false; }
    },
    async remove(id) {
      try {
        await RecipeApp.api('/api/inventory/' + id, { method: 'DELETE' });
        await this.load();
      } catch (e) {}
    },
  };
}

/* ===== 日志抽屉（全局 store + 全局函数供菜单按钮调用） ===== */
function logsDrawerStore() {
  return {
    open: false,
    loading: false,
    logs: [],
    filter: 'ALL',

    get visibleLogs() {
      if (this.filter === 'ALL') return this.logs;
      return this.logs.filter(function (l) { return l.level === this.filter; }.bind(this));
    },

    async load() {
      this.loading = true;
      try {
        const res = await fetch('/api/app/logs?limit=200', {
          headers: { 'Authorization': 'Bearer ' + (localStorage.getItem('recipe_token') || '') },
        });
        if (res.ok) {
          const d = await res.json();
          this.logs = (d.logs || []).reverse();
        } else {
          this.logs = [];
        }
      } catch (e) {
        this.logs = [];
      } finally {
        this.loading = false;
      }
    },

    close() {
      this.open = false;
    },

    async clearAll() {
      if (!window.__confirm) { if (!confirm('确定清空所有日志吗？')) return; }
      else {
        await new Promise(function (resolve) {
          window.__confirm({
            title: '清空日志',
            message: '确定清空所有运行日志吗？操作不可撤销。',
            onOk: function () { resolve(true); },
            onCancel: function () { resolve(false); },
          });
        });
      }
      try {
        const res = await fetch('/api/app/logs', {
          method: 'DELETE',
          headers: { 'Authorization': 'Bearer ' + (localStorage.getItem('recipe_token') || '') },
        });
        if (res.ok || res.status === 204) {
          this.logs = [];
          this.load();
        }
      } catch (e) { /* 忽略 */ }
    },
  };
}

/* 在 Alpine 启动前注册 store，供 base.html 用 x-data="$store.logsDrawer" 引用 */
document.addEventListener('alpine:init', function () {
  Alpine.store('logsDrawer', logsDrawerStore());
  window.openLogsDrawer = function () {
    var s = Alpine.store('logsDrawer');
    s.open = true;
    s.filter = 'ALL';
    s.load();
  };
});
