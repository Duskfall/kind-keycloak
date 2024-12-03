kubectl create secret generic oauth-token --from-literal=client-secret=PBXkvJ8msmI0DhGrDIkoxHXtPBZKdg6x -n istio-system

http://localhost:30002/realms/master/protocol/openid-connect/auth?client_id=bookinfo&response_type=code&scope=openid%20profile%20email&redirect_uri=http://localhost:30000/productpage&state=someRandomState


// browser
const urlParams = new URLSearchParams(window.location.search);
const code = urlParams.get('code');  // This gets the code from the URL

// 2. Then exchange the code for a token
if (code) {
  fetch('http://localhost:30002/realms/master/protocol/openid-connect/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: 'bookinfo',
      code: code,  // Using the code we got from the URL
      redirect_uri: 'http://localhost:30000/productpage'
    })
  })
  .then(response => response.json())
  .then(data => {
    localStorage.setItem('access_token', data.access_token);
    // Now you can make your API request with the token
  })
  .catch(error => console.error('Error:', error));


  then

  fetch("http://localhost:30000/api/v1/products/0/reviews", {
  "headers": {
    "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "accept-language": "en",
    "cache-control": "no-cache",
    "pragma": "no-cache",
    "Authorization": "Bearer " + localStorage.getItem('access_token'), // Add this line
    "sec-ch-ua": "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": "\"Windows\"",
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "none",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1"
  },
  "referrerPolicy": "strict-origin-when-cross-origin",
  "body": null,
  "method": "GET",
  "mode": "cors",
  "credentials": "include"  // Changed from "omit" to "include"
})
.then(response => response.json())
.then(data => console.log(data))
.catch(error => console.error('Error:', error));