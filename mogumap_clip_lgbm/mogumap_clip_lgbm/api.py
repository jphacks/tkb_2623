"""Development-only authenticated API. Do not expose to the public internet."""
import os
from threading import Lock
from typing import Any
from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field
from ml import train, predict, ARTIFACT

app = FastAPI(title='MoguMap CLIP + LightGBM API', version='0.1')
train_lock = Lock()

def auth(x_api_key: str | None = Header(default=None)):
    key = os.getenv('MOGUMAP_API_KEY')
    if not key or x_api_key != key:
        raise HTTPException(401, 'Invalid API key or MOGUMAP_API_KEY not configured')

class TrainRequest(BaseModel):
    records: list[dict[str, Any]] = Field(min_length=30, max_length=10000)

class PredictRequest(BaseModel):
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)
    candidates: list[dict[str, Any]] = Field(min_length=1, max_length=100)

@app.get('/health')
def health():
    return {'status': 'ok', 'trained': ARTIFACT.exists()}

@app.post('/train', dependencies=[Depends(auth)])
def train_endpoint(body: TrainRequest):
    if not train_lock.acquire(blocking=False):
        raise HTTPException(409, 'training already running')
    try:
        return train(body.records)
    except (ValueError, OSError) as e:
        raise HTTPException(400, str(e))
    finally:
        train_lock.release()

@app.post('/predict', dependencies=[Depends(auth)])
def predict_endpoint(body: PredictRequest):
    try:
        return {'predictions': predict(body.history, body.candidates)}
    except FileNotFoundError as e:
        raise HTTPException(409, str(e))
    except (ValueError, OSError) as e:
        raise HTTPException(400, str(e))
