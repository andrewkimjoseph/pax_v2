(function() {
  // Prevent overwriting by other scripts (either ethereum or PaxWallet already set)
  if ((window.ethereum && window.ethereum.isFlutterWeb3) ||
      (window.PaxWallet && window.PaxWallet.isFlutterWeb3)) {
    return; // Already injected
  }
  
  
  // Event listeners storage
  const eventListeners = {
    accountsChanged: [],
    chainChanged: [],
    connect: [],
    disconnect: []
  };
  
  // Create a custom Web3 Provider that communicates with Flutter
  const ethereumProvider = {
    isFlutterWeb3: true,
    isMetaMask: true, // Some dApps check for this
    isMiniPay: true,   // Mimic MiniPay for mini-app compatibility
    isMinipay: true,   // Alternate spelling some sites use
    _metamask: {
      isUnlocked: async () => true,
      requestBatch: async (requests) => {
        return Promise.all(requests.map(req => ethereumProvider.request(req)));
      }
    },
    selectedAddress: null,
    chainId: null,
    networkVersion: null,
    
    // Check if provider is connected
    isConnected: function() {
      return this.selectedAddress !== null;
    },
    
    // Request accounts from Flutter
    request: async function(args) {
      // Handle both object and direct method calls
      const method = typeof args === 'string' ? args : args.method;
      const params = typeof args === 'string' ? [] : (args.params || []);
      
      return new Promise((resolve, reject) => {
        const messageId = Date.now().toString() + Math.random().toString(36).substr(2, 9);
        
        const timeout = setTimeout(() => {
          if (window.web3Callbacks[messageId]) {
            delete window.web3Callbacks[messageId];
            reject(new Error('Request timeout'));
          }
        }, 30000);
        
        window.web3Callbacks = window.web3Callbacks || {};
        window.web3Callbacks[messageId] = { resolve, reject, timeout };
        
        // Send message to Flutter
        try {
          window.flutter_inappwebview.callHandler('web3Request', {
            id: messageId,
            method: method,
            params: params
          }).then(() => {
            // Request sent successfully
          }).catch((error) => {
            clearTimeout(timeout);
            if (window.web3Callbacks && window.web3Callbacks[messageId]) {
              delete window.web3Callbacks[messageId];
            }
            reject(new Error('Failed to send request: ' + error));
          });
        } catch (error) {
          clearTimeout(timeout);
          if (window.web3Callbacks && window.web3Callbacks[messageId]) {
            delete window.web3Callbacks[messageId];
          }
          reject(new Error('Provider not available: ' + error));
        }
      });
    },
    
    // Legacy methods for compatibility
    enable: function() {
      return this.request({ method: 'eth_requestAccounts' });
    },
    
    send: function(method, params) {
      if (typeof method === 'string') {
        return this.request({ method, params: params || [] });
      } else {
        // Legacy format: send(payload, callback)
        const payload = method;
        const callback = params;
        this.request(payload)
          .then(result => callback(null, { id: payload.id, result }))
          .catch(error => callback(error, null));
      }
    },
    
    sendAsync: function(payload, callback) {
      this.request(payload)
        .then(result => callback(null, { id: payload.id, result }))
        .catch(error => callback(error, null));
    },
    
    // Event emitter methods
    on: function(event, callback) {
      if (eventListeners[event]) {
        eventListeners[event].push(callback);
      }
    },
    
    removeListener: function(event, callback) {
      if (eventListeners[event]) {
        const index = eventListeners[event].indexOf(callback);
        if (index > -1) {
          eventListeners[event].splice(index, 1);
        }
      }
    },
    
    removeAllListeners: function(event) {
      if (event) {
        eventListeners[event] = [];
      } else {
        Object.keys(eventListeners).forEach(key => {
          eventListeners[key] = [];
        });
      }
    },
    
    // Emit events (called from Flutter)
    _emit: function(event, data) {
      if (eventListeners[event]) {
        eventListeners[event].forEach(callback => {
          try {
            callback(data);
          } catch (e) {
            console.error('Error in event listener:', e);
          }
        });
      }
    }
  };
  
  // Expose as PaxWallet for explicit use in web3 operations; ethereum for dApp compatibility
  try {
    window.PaxWallet = ethereumProvider;
  } catch (e) {
    window.PaxWallet = ethereumProvider;
  }
  
  // Legacy: some dApps expect window.ethereum
  try {
    Object.defineProperty(window, 'ethereum', {
      value: ethereumProvider,
      writable: false,
      configurable: false,
      enumerable: true
    });
  } catch (e) {
    window.ethereum = ethereumProvider;
  }
  
  // Also set web3 for legacy support (use PaxWallet as the provider)
  if (!window.web3) {
    window.web3 = {
      currentProvider: window.PaxWallet || ethereumProvider,
      eth: {
        accounts: [],
        getAccounts: function(callback) {
          (window.PaxWallet || ethereumProvider).request({ method: 'eth_accounts' })
            .then(accounts => callback(null, accounts))
            .catch(error => callback(error, null));
        }
      }
    };
  }
  
  // Handle responses from Flutter
  window.handleWeb3Response = function(response) {
    const callback = window.web3Callbacks && window.web3Callbacks[response.id];
    if (callback) {
      if (callback.timeout) clearTimeout(callback.timeout);
      if (response.error) {
        // Handle error object with code and message
        const error = typeof response.error === 'object' 
          ? new Error(response.error.message || JSON.stringify(response.error))
          : new Error(response.error);
        if (response.error.code) {
          error.code = response.error.code;
        }
        callback.reject(error);
      } else {
        callback.resolve(response.result);
      }
      delete window.web3Callbacks[response.id];
    }
  };
  
  // Dispatch connect event immediately if address is set
  const provider = window.PaxWallet || ethereumProvider;
  if (provider.selectedAddress) {
    setTimeout(() => {
      provider._emit('connect', { chainId: provider.chainId });
    }, 0);
  }
})();