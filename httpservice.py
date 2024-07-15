from flask import Flask, Response, jsonify
import os, json

app = Flask(__name__)

@app.route('/')
def index():
    return "200, OK!"

@app.errorhandler(Exception)
def handle_error(error):
    return jsonify({"error": str(error)}), 500

@app.route('/log/<id>')
def get_logs(id):
    try:
        if len(id) < 8 or len(id) > 9:
            raise ValueError("ID should be 8 or 9 bytes")
        port = id[:-4]
        pcode = id[-4:]
        # read conf file
        conf_path = os.path.join("/etc/shadowsocks-libev", f'{port}.json')
        if not os.path.exists(conf_path):
            raise ValueError(f'{conf_path} does not exist')
        with open(conf_path, 'r') as f:
            data = json.load(f)
            passcode = data["password"]

        if pcode != passcode[:4]:
            raise ValueError(f'ID is invalid')
        # read log file
        log_path = os.path.join(os.path.dirname(__file__), f'log/{port}.log')
        if not os.path.exists(log_path):
            raise ValueError(f'{log_path} does not exist')
        # two lines at least
        with open(log_path, 'r') as f:
            first_line = next(iter(f))
            lines = []
            i = 0
            # jump to file's end
            f.seek(0, 2)
            # skip the last \n
            pos = f.tell() - 2
            while pos > 0:
                f.seek(pos, 0)
                if f.read(1) == '\n':
                    lines = [f.readline().strip()] + lines
                    # output lines at maxinum
                    i += 1
                    if i == 20:
                        break
                pos -= 1
            lines = [first_line.strip()] + lines
        return Response('\n'.join(lines), mimetype='text/plain')
    except Exception as e:
        return handle_error(e)

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000, debug=True)
