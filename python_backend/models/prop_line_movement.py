from pydantic import BaseModel, Field

from models.prop_builder import PropBuilderLeg


class PropLineMovementRequest(BaseModel):
    legs: list[PropBuilderLeg] = Field(
        default_factory=list,
    )


class PropLineMovementResponse(BaseModel):
    legs: list[PropBuilderLeg] = Field(
        default_factory=list,
    )
    checked_count: int = 0
    changed_count: int = 0
    unavailable_count: int = 0
