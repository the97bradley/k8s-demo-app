
login = document.getElementById("loginbtn");
signup = document.getElementById("signupbtn");
login.addEventListener("click", () => {
    fetch("/login", {
        method : 'POST',
        headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          },
        body : JSON.stringify( {
            'email' : document.getElementById("loginemail").value,
            'password' : document.getElementById("loginpass").value,
        })
    })
    .then(async response => {
        if(response.status == 200) {
            window.location.href = "/todo";
        } else {
            let body = await response.json();
            if(body.error) {
                console.error(body.error);
                document.getElementById('error').innerHTML=body.error;
            }
            // var str = JSON.stringify(response.json());
            // document.write(str)
        }
        
    })
    .catch(error => {
        console.error(error);
    })
});

signup.addEventListener("click", () => {
    fetch("/signup", {
        method: 'POST',
        headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            'username': document.getElementById("signupname").value,
            'email': document.getElementById("signupemail").value,
            'password': document.getElementById("signuppass").value
        })
    })
    .then(async response => {
        if (response.ok) {
            window.location.href = "/todo";
        } else {
            console.error("Error Response Status:", response.status, response.statusText);
            
            let contentType = response.headers.get("content-type");
            if (contentType && contentType.indexOf("application/json") !== -1) {
                let body = await response.json();
                if (body.error) {
                    console.error("Error Response Body:", body);
                    document.getElementById('error').innerHTML = body.error;
                }
            } else {
                let text = await response.text();
                console.error("Unexpected response format:", text);
                document.getElementById('error').innerHTML = "Unexpected response: " + text;
            }
        }
    })
    .catch(error => {
        console.error("Fetch Error:", error);
        document.getElementById('error').innerHTML = "An unexpected error occurred. Please try again.";
    });
});

